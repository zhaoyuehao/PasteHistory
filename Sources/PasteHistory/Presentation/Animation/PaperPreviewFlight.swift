import AppKit
import QuartzCore

/// Geometry is the actual sheet, not the axis-aligned window around a tilted card.
struct PaperPose {
    var pin: NSPoint
    var size: NSSize
    var angle: CGFloat = 0
    var inset: CGFloat = IvoryPaperStyle.pinInset
    var padding: CGFloat = 0

    init(pin: NSPoint, size: NSSize, angle: CGFloat = 0,
         inset: CGFloat = IvoryPaperStyle.pinInset, padding: CGFloat = 0) {
        self.pin = pin; self.size = size; self.angle = angle
        self.inset = inset; self.padding = padding
    }
    init(frame: NSRect, inset: CGFloat = IvoryPaperStyle.pinInset) {
        self.init(pin: NSPoint(x: frame.midX, y: frame.maxY - inset), size: frame.size, inset: inset)
    }
    var frame: NSRect {
        let corners = [NSPoint(x: -size.width/2, y: inset), NSPoint(x: size.width/2, y: inset),
                       NSPoint(x: -size.width/2, y: inset-size.height), NSPoint(x: size.width/2, y: inset-size.height)]
        let points = corners.map { NSPoint(x: pin.x + $0.x*cos(angle) - $0.y*sin(angle),
                                          y: pin.y + $0.x*sin(angle) + $0.y*cos(angle)) }
        let left = points.map(\.x).min()!, bottom = points.map(\.y).min()!
        return NSRect(x: left-padding, y: bottom-padding,
                      width: points.map(\.x).max()!-left+2*padding,
                      height: points.map(\.y).max()!-bottom+2*padding)
    }
    var channels: [CGFloat] { [pin.x, pin.y, size.width, size.height, angle, inset, padding] }
    init(channels: [CGFloat]) {
        self.init(pin: NSPoint(x: channels[0], y: channels[1]),
                  size: NSSize(width: max(1, channels[2]), height: max(1, channels[3])),
                  angle: channels[4], inset: channels[5], padding: max(0, channels[6]))
    }
}

/// The same retained layer renderer as the source paper. The native window is
/// bounded to the visible paper for click-through; resizing it does not redraw faces.
final class PaperFlightView: NSView {
    var pose = PaperPose(frame: .zero)
    var readingImage: NSImage?
    var compactImage: NSImage?
    var compactColor = IvoryPaperStyle.fill
    var expansion: CGFloat = 1
    private let faces = PaperFaceLayers()
    private var canvas = NSRect.zero
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(faces.root)
    }
    required init?(coder: NSCoder) { fatalError() }
    func place(_ pose: PaperPose, in panel: NSPanel) {
        if panel.frame != pose.frame.integral { panel.setFrame(pose.frame.integral, display: false) }
        place(pose, canvas: panel.frame)
    }
    func place(_ pose: PaperPose, canvas: NSRect) {
        let shapeChanged = self.pose.size != pose.size || self.pose.angle != pose.angle || self.pose.inset != pose.inset
        self.pose = pose
        self.canvas = canvas
        updateFaces()
        if shapeChanged { window?.invalidateShadow() }
    }
    private func updateFaces() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        faces.images(compact: compactImage, reading: readingImage)
        faces.place(pose, canvas: canvas, expansion: expansion, compactColor: compactColor,
                    backingScale: window?.backingScaleFactor ?? 2)
        CATransaction.commit()
    }
    func faceImage() -> NSImage {
        let saved = canvas
        canvas = pose.frame
        updateFaces()
        let image = NSImage(size: canvas.size)
        image.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext { faces.root.render(in: context) }
        image.unlockFocus()
        canvas = saved
        updateFaces()
        return image
    }
}

/// One state and display clock own flight, live following and gesture release.
/// The native windows remain tightly bounded input surfaces. Their contents are
/// retained layers; geometry changes never capture or redraw the paper faces.
@MainActor
final class PaperPreviewFlight {
    struct FrameSample {
        let delta: Double
        let work: Double
        let pose: PaperPose
        let windowFrame: NSRect
        let expansion: CGFloat
        let finished: Bool
    }
    var observeFrame: ((FrameSample) -> Void)?
    var onToggle: (() -> Void)?
    var onMagnify: ((CGFloat, NSEvent.Phase) -> Bool)?
    private var window: PaperPreviewPanel?
    private var sheet: PaperFlightView?
    private weak var liveWindow: NSPanel?
    private let clock = MotionClock()
    private let reduceMotion: () -> Bool
    private var clockRunning = false
    private var motion: DampedMotion?
    private var completion: (() -> Void)?
    private var generation = 0
    private var recordID: UUID?
    private var flying = false
    private var reduced = false
    private var fade: SettlingTrack?
    private var fadeElapsed = 0.0
    private var lastDirectTime = 0.0
    private let tolerances: [CGFloat] = [0.2, 0.2, 0.2, 0.2, 0.0002, 0.002, 0.05, 0.0005, 0.001]
    var visibleFrame: NSRect? { flying && window?.isVisible == true ? window?.frame : nil }
    var visiblePose: PaperPose? { visibleFrame == nil ? nil : sheet?.pose }

    init(reduceMotion: @escaping () -> Bool = { Motion.reduceMotion }) { self.reduceMotion = reduceMotion }
    deinit { MainActor.assumeIsolated { clock.stop(); window?.endPaperInteraction() } }

    func isAnimating(recordID: UUID?) -> Bool { visiblePose != nil && self.recordID == recordID }
    func cancel() {
        generation += 1
        stopClock()
        window?.endPaperInteraction()
        window?.orderOut(nil)
        liveWindow = nil; motion = nil; completion = nil; flying = false
    }
    private func stopClock() { clock.stop(); clockRunning = false }
    private func startClock(on panel: NSWindow) {
        guard !clockRunning else { return }
        clockRunning = true
        clock.start(on: panel) { [weak self] frame in self?.step(frame) }
    }
    private func newMotion(_ values: [CGFloat]) -> DampedMotion {
        DampedMotion(values: values,
                     frequency: Motion.paperFrequency, anchorTime: Motion.paperAnchorTime)
    }

    func animate(from: PaperPose, to: PaperPose, readingImage: NSImage?, compactImage: NSImage? = nil,
                 compactColor: NSColor? = nil, recordID: UUID? = nil, opening: Bool,
                 onReady: () -> Void = {}, completion: @escaping () -> Void) {
        generation += 1
        let wasFlying = visiblePose != nil
        let retainFace = wasFlying && self.recordID == recordID
        let inheritLive = !wasFlying && liveWindow?.isVisible == true && motion != nil
        let reduce = reduceMotion()
        let target = to.channels + [opening ? 1 : 0, reduce && !opening ? 0 : 1]
        if !wasFlying {
            let initial = from.channels + [opening ? 0 : 1, reduce && opening ? 0 : 1]
            if inheritLive { motion?.align(to: initial) }
            else { motion = newMotion(initial) }
        }
        motion?.retarget(target)
        self.completion = completion
        self.recordID = recordID
        reduced = reduce
        if reduce {
            fade = SettlingTrack(start: window?.alphaValue ?? (opening ? 0 : 1), end: opening ? 1 : 0,
                                 duration: Motion.paperFadeDuration, symmetric: true)
            if !wasFlying { fade?.start = opening ? 0 : 1 }
            fadeElapsed = 0
        } else { fade = nil }
        let panel: PaperPreviewPanel
        let face: PaperFlightView
        if let window, let sheet { panel = window; face = sheet }
        else {
            panel = PaperPreviewPanel(contentRect: from.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.acceptsKeyboardFocus = false
            panel.isReleasedWhenClosed = false
            panel.title = "纸签预览过渡"
            panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.onCollapse = { [weak self] in self?.onToggle?() }
            panel.onMagnify = { [weak self] delta, phase in self?.onMagnify?(delta, phase) ?? false }
            face = PaperFlightView(frame: NSRect(origin: .zero, size: from.frame.size))
            face.autoresizingMask = [.width, .height]
            panel.contentView = face
            window = panel; sheet = face
        }
        if !retainFace {
            face.readingImage = readingImage; face.compactImage = compactImage
            face.compactColor = compactColor ?? IvoryPaperStyle.fill
        }
        if !wasFlying {
            face.expansion = reduce ? 1 : (opening ? 0 : 1)
            face.place(reduce && opening ? to : from, in: panel)
            panel.alphaValue = reduce && opening ? 0 : 1
            panel.orderFrontRegardless()
        }
        flying = true
        liveWindow = nil
        panel.ignoresMouseEvents = false
        panel.beginPaperInteraction()
        // Commit the starting layers in the same transaction as the source handoff.
        CATransaction.flush()
        onReady()
        startClock(on: panel)
    }

    /// Layout and magnification retarget the same flight without capturing faces.
    func retargetFlight(to pose: PaperPose, opening: Bool, compactImage: NSImage? = nil, compactColor: NSColor? = nil) {
        guard flying else { return }
        // A departing source may change selection/height while we return to it.
        // Reuse its cached face so the last frame still matches that actual card.
        if !opening {
            if let compactImage { sheet?.compactImage = compactImage }
            if let compactColor { sheet?.compactColor = compactColor }
        }
        motion?.retarget(pose.channels + [opening ? 1 : 0, reduced && !opening ? 0 : 1])
    }

    func moveLive(_ panel: NSPanel, to pose: PaperPose) {
        guard !flying else { return }
        fade = nil
        liveWindow = panel
        let target = pose.channels + [1, 1]
        if motion == nil { motion = newMotion(PaperPose(frame: panel.frame, inset: pose.inset).channels + [1, 1]) }
        motion?.retarget(target)
        if reduceMotion() {
            motion?.finish()
            panel.setFrame(pose.frame, display: false)
            stopClock()
        } else if motion?.isSettled(tolerances: tolerances) == false { startClock(on: panel) }
    }
    func trackLive(_ panel: NSPanel, pose: PaperPose) {
        guard !flying else { retargetFlight(to: pose, opening: true); return }
        stopClock()
        liveWindow = panel
        let now = CACurrentMediaTime()
        if motion == nil { motion = newMotion(pose.channels + [1, 1]) }
        motion?.track(pose.channels + [1, 1], delta: now-lastDirectTime)
        lastDirectTime = now
        panel.setFrame(pose.frame, display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    private func step(_ frame: MotionClock.Frame) {
        guard motion != nil else { stopClock(); return }
        let began = observeFrame == nil ? 0 : CACurrentMediaTime()
        motion?.advance(by: frame.delta)
        fadeElapsed += frame.delta
        let finished = fade.map { fadeElapsed >= $0.duration } ?? (motion?.isSettled(tolerances: tolerances) == true)
        if finished { motion?.finish() }
        guard let values = motion?.values else { return }
        let pose = PaperPose(channels: Array(values.prefix(7)))
        if flying, let panel = window, let face = sheet {
            face.expansion = reduced ? 1 : values[7]
            if !reduced { face.place(pose, in: panel) }
            panel.alphaValue = fade.map { min(1,max(0,$0.sample(fadeElapsed).value)) } ?? 1
            observeFrame?(FrameSample(delta: frame.delta, work: CACurrentMediaTime()-began,
                pose: face.pose, windowFrame: panel.frame, expansion: face.expansion, finished: finished))
            if finished {
                stopClock()
                flying = false
                panel.endPaperInteraction()
                let completedGeneration = generation
                let done = completion; completion = nil
                // The new surface is made visible before the retained flight leaves.
                done?()
                if generation == completedGeneration { panel.orderOut(nil) }
            }
        } else if let panel = liveWindow, panel.isVisible {
            panel.setFrame(pose.frame, display: false)
            panel.contentView?.layoutSubtreeIfNeeded()
            observeFrame?(FrameSample(delta: frame.delta, work: CACurrentMediaTime()-began,
                pose: pose, windowFrame: panel.frame, expansion: 1, finished: finished))
            if finished { stopClock() }
        } else { stopClock() }
    }
}
