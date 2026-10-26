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

/// Retained card renderer with an optional live reading document. Its window
/// remains bounded to the paper; content keeps fixed logical reading coordinates.
final class PaperFlightView: NSView {
    var pose = PaperPose(frame: .zero)
    var compactImage: NSImage?
    var compactColor = IvoryPaperStyle.fill
    var expansion: CGFloat = 1
    private let faces = PaperFaceLayers()
    private var canvas = NSRect.zero
    private(set) var readingSurface: PaperPreviewSurface?
    var acceptsReadingInput = false
    var measuresRenderingWork = false
    private(set) var windowUpdateWork = 0.0
    private(set) var faceUpdateWork = 0.0
    private(set) var shadowUpdateWork = 0.0
    private var readingLogicalSize: NSSize?
    private var readingDisplaySize: NSSize?
    private var readingAngle: CGFloat?

    func attachReading(_ surface: PaperPreviewSurface) {
        guard readingSurface !== surface else { return }
        readingSurface?.removeFromSuperview()
        readingSurface = surface
        readingLogicalSize = nil
        readingDisplaySize = nil
        readingAngle = nil
        addSubview(surface)
        updateFaces()
        surface.prepareReadingLayout()
    }
    func detachReading() {
        readingSurface?.removeFromSuperview()
        readingSurface = nil
    }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard acceptsReadingInput else { return nil }
        return super.hitTest(point)
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(faces.root)
    }
    required init?(coder: NSCoder) { fatalError() }
    func place(_ pose: PaperPose, in panel: NSPanel) {
        let began = measuresRenderingWork ? CACurrentMediaTime() : 0
        if panel.frame != pose.frame.integral { panel.setFrame(pose.frame.integral, display: false) }
        windowUpdateWork = measuresRenderingWork ? CACurrentMediaTime()-began : 0
        place(pose, canvas: panel.frame)
    }
    func place(_ pose: PaperPose, canvas: NSRect) {
        let shapeChanged = self.pose.size != pose.size || self.pose.angle != pose.angle || self.pose.inset != pose.inset
        self.pose = pose
        self.canvas = canvas
        let began = measuresRenderingWork ? CACurrentMediaTime() : 0
        updateFaces()
        let drew = measuresRenderingWork ? CACurrentMediaTime() : 0
        if shapeChanged { window?.invalidateShadow() }
        faceUpdateWork = measuresRenderingWork ? drew-began : 0
        shadowUpdateWork = measuresRenderingWork ? CACurrentMediaTime()-drew : 0
    }
    private func updateFaces() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        faces.image(compactImage)
        faces.place(pose, canvas: canvas, expansion: expansion, compactColor: compactColor,
                    backingScale: window?.backingScaleFactor ?? 2, liveReading: readingSurface != nil)
        if let surface = readingSurface {
            let logical = surface.readingSize ?? pose.size
            let scale = min(pose.size.width / logical.width, pose.size.height / logical.height)
            let displaySize = NSSize(width: logical.width * scale, height: logical.height * scale)
            if readingDisplaySize != displaySize || readingAngle != pose.angle || readingLogicalSize != logical {
                // Translation-only following must not invalidate the document's
                // scale/rotation. Keep logical bounds fixed while resizing.
                if surface.frameRotation != 0 { surface.frameRotation = 0 }
                if readingDisplaySize != displaySize { surface.setFrameSize(displaySize) }
                if surface.bounds.size != logical { surface.setBoundsSize(logical) }
                let degrees = pose.angle * 180 / .pi
                if surface.frameRotation != degrees { surface.frameRotation = degrees }
                readingDisplaySize = displaySize
                readingAngle = pose.angle
                readingLogicalSize = logical
            }
            let pin = surface.convert(NSPoint(x: logical.width / 2,
                y: logical.height - IvoryPaperStyle.pinInset), to: self)
            surface.setFrameOrigin(NSPoint(x: surface.frame.origin.x + pose.pin.x - canvas.minX - pin.x,
                y: surface.frame.origin.y + pose.pin.y - canvas.minY - pin.y))
            surface.alphaValue = PaperFaceLayers.blend(expansion)
        }
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

/// Drives the existing card window. Opening/closing never creates a window,
/// captures the live document, or exchanges surfaces at the settling boundary.
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
    private weak var window: NSPanel?
    private weak var sheet: PaperFlightView?
    private let clock = MotionClock()
    private var clockRunning = false
    private var trace = PaperMotionTrace()
    private let reduceMotion: () -> Bool
    private var motion: DampedMotion?
    private var completion: (() -> Void)?
    private var generation = 0
    private var flying = false
    private var opening = true
    private var reduced = false
    private var fade: SettlingTrack?
    private var fadeElapsed = 0.0
    private var lastDirectTime = 0.0
    private let tolerances: [CGFloat] = [0.2, 0.2, 0.2, 0.2, 0.0002, 0.002, 0.05, 0.0005]
    var visibleFrame: NSRect? { flying && window?.isVisible == true ? window?.frame : nil }
    var visiblePose: PaperPose? { visibleFrame == nil ? nil : sheet?.pose }
    var currentPose: PaperPose? { sheet?.pose }

    init(reduceMotion: @escaping () -> Bool = { Motion.reduceMotion }) { self.reduceMotion = reduceMotion }
    deinit { MainActor.assumeIsolated { clock.stop() } }

    func bind(window: NSPanel, sheet: PaperFlightView) {
        generation += 1
        stopClock()
        self.window = window
        self.sheet = sheet
        sheet.measuresRenderingWork = trace.enabled
        motion = nil
        completion = nil
        flying = false
    }
    func cancel() {
        generation += 1
        trace.finish(reason: "cancelled")
        stopClock()
        completion = nil
        flying = false
        motion = nil
        window = nil
        sheet = nil
    }
    private func newMotion(_ values: [CGFloat]) -> DampedMotion {
        DampedMotion(values: values, frequency: Motion.paperFrequency, anchorTime: Motion.paperAnchorTime)
    }
    private func stopClock() { clock.stop(); clockRunning = false }
    private func startClock() {
        guard !clockRunning, let window else { return }
        clockRunning = true
        clock.start(on: window) { [weak self] frame in self?.step(frame) }
    }
    func animate(to pose: PaperPose, opening: Bool, completion: @escaping () -> Void) {
        guard let sheet else { return }
        generation += 1
        trace.begin(opening: opening, refreshRate: window?.screen?.maximumFramesPerSecond ?? 60)
        self.opening = opening
        self.completion = completion
        reduced = reduceMotion()
        if motion == nil { motion = newMotion(sheet.pose.channels + [sheet.expansion]) }
        motion?.retarget(pose.channels + [opening ? 1 : 0])
        if reduced {
            fade = SettlingTrack(start: sheet.expansion, end: opening ? 1 : 0,
                                 duration: Motion.paperFadeDuration, symmetric: true)
            fadeElapsed = 0
            // Reduce Motion changes geometry once and dissolves content within
            // the same opaque paper, without fading the entire window away.
            if opening, let window { sheet.place(pose, in: window) }
        } else { fade = nil }
        flying = true
        setReadingInput(false)
        startClock()
    }
    func retargetFlight(to pose: PaperPose, opening: Bool) {
        guard flying else { return }
        motion?.retarget(pose.channels + [opening ? 1 : 0])
    }
    func moveLive(_ panel: NSPanel, to pose: PaperPose) {
        guard !flying, let sheet else { return }
        let target = pose.channels + [1]
        if motion == nil { motion = newMotion(sheet.pose.channels + [1]) }
        motion?.retarget(target)
        if reduceMotion() {
            motion?.finish()
            sheet.place(pose, in: panel)
            stopClock()
        } else if motion?.isSettled(tolerances: tolerances) == false { startClock() }
    }
    func trackLive(_ panel: NSPanel, pose: PaperPose) {
        guard !flying else { retargetFlight(to: pose, opening: true); return }
        stopClock()
        let now = CACurrentMediaTime()
        if motion == nil { motion = newMotion(pose.channels + [1]) }
        motion?.track(pose.channels + [1], delta: now-lastDirectTime)
        lastDirectTime = now
        sheet?.place(pose, in: panel)
    }
    private func setReadingInput(_ enabled: Bool) {
        sheet?.acceptsReadingInput = enabled
        // Eligibility only: never make the preview key or steal search focus.
        (window as? PaperPreviewPanel)?.acceptsKeyboardFocus = enabled
    }

    private var readyForReading: Bool {
        guard let motion, let sheet, sheet.expansion >= Motion.paperReadingExpansion else { return false }
        let target = PaperPose(channels: Array(motion.destination.prefix(7)))
        // Absolute position bounds and relative size bounds avoid enabling
        // selection while a redirected paper is still crossing the screen.
        let errors: [CGFloat] = [4, 4, max(2, target.size.width * 0.01),
            max(2, target.size.height * 0.01), 0.002, 0.1, 0.2]
        let speeds: [CGFloat] = [60, 60, 100, 100, 0.02, 2, 4]
        return errors.indices.allSatisfy { index in
            let state = motion.states[index]
            return abs(state.value - motion.destination[index]) <= errors[index]
                && abs(state.velocity) <= speeds[index]
        }
    }

    private func step(_ frame: MotionClock.Frame) {
        guard let panel = window, panel.isVisible, let sheet, motion != nil else {
            stopClock(); return
        }
        let frameGeneration = generation
        let began = observeFrame == nil && !trace.enabled ? 0 : CACurrentMediaTime()
        motion?.advance(by: frame.delta)
        fadeElapsed += frame.delta
        let finished = flying && reduced
            ? fadeElapsed >= (fade?.duration ?? 0)
            : motion?.isSettled(tolerances: tolerances) == true
        if finished { motion?.finish() }
        guard let values = motion?.values else { return }
        let pose = PaperPose(channels: Array(values.prefix(7)))
        sheet.expansion = flying && reduced
            ? min(1, max(0, fade?.sample(fadeElapsed).value ?? values[7])) : values[7]
        sheet.place(flying && reduced && !finished ? sheet.pose : pose, in: panel)
        // The small remaining settling motion must not delay native text/scroll
        // input. Enable once near the target; do not flap during small retargets.
        if opening, !sheet.acceptsReadingInput, finished || readyForReading {
            setReadingInput(true)
        }
        trace.record(callbackTime: began, delta: frame.delta,
            work: trace.enabled ? CACurrentMediaTime()-began : 0,
            windowWork: sheet.windowUpdateWork, faceWork: sheet.faceUpdateWork,
            shadowWork: sheet.shadowUpdateWork, expansion: sheet.expansion)
        observeFrame?(FrameSample(delta: frame.delta, work: CACurrentMediaTime()-began,
            pose: sheet.pose, windowFrame: panel.frame, expansion: sheet.expansion, finished: finished))
        guard finished, generation == frameGeneration else { return }
        trace.finish(reason: "settled")
        stopClock()
        let done = completion
        completion = nil
        flying = false
        setReadingInput(opening)
        // No visibility, window ordering, image replacement or shadow handoff.
        // Clear state before calling out so a reentrant opening owns its completion.
        done?()
    }
}
