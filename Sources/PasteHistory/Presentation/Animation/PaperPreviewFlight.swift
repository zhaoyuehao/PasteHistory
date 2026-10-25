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

/// One paper renderer for BOTH directions. The phase determines geometry's
/// content counterpart: compact face -> reading face, and the exact reverse.
/// Each layout is uniformly scaled; paragraphs never reflow or stretch sideways.
final class PaperFlightView: NSView {
    var pose = PaperPose(frame: .zero)
    var readingImage: NSImage?
    var compactImage: NSImage?
    var expansion: CGFloat = 1
    private var canvasOrigin: NSPoint?
    override var isOpaque: Bool { false }

    func place(_ pose: PaperPose, in panel: NSPanel) {
        self.pose = pose
        panel.setFrame(pose.frame.integral, display: false)
        canvasOrigin = panel.frame.origin
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let origin = canvasOrigin ?? pose.frame.origin
        drawPaper(pin: NSPoint(x: pose.pin.x-origin.x, y: pose.pin.y-origin.y))
    }
    private func drawPaper(pin: NSPoint) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: pin.x, y: pin.y)
        let scale = pose.inset / IvoryPaperStyle.pinInset
        let rect = NSRect(x: -pose.size.width/2, y: pose.inset-pose.size.height,
                          width: pose.size.width, height: pose.size.height)
        func outline(in bounds: NSRect, radius: CGFloat) -> NSBezierPath {
            let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
            path.transform(using: AffineTransform(rotationByRadians: pose.angle))
            return path
        }
        let paper = outline(in: rect, radius: IvoryPaperStyle.radius * scale)
        IvoryPaperStyle.fill.setFill(); paper.fill()
        context.saveGState()
        paper.addClip()
        func drawFace(_ image: NSImage?, opacity: CGFloat, angle: CGFloat, compact: Bool = false) {
            guard let image, opacity > 0 else { return }
            let fit = min(compact ? 1 : CGFloat.greatestFiniteMagnitude,
                          rect.width/max(1, image.size.width), rect.height/max(1, image.size.height))
            let size = NSSize(width: image.size.width*fit, height: image.size.height*fit)
            let frame = NSRect(x: compact ? rect.minX : -size.width/2, y: rect.maxY-size.height, width: size.width, height: size.height)
            context.saveGState()
            context.rotate(by: angle)
            // The shell owns the edge and suspension hole. Content layers have
            // no separate rectangular chrome, and neither stretches its glyphs.
            NSBezierPath(rect: NSRect(x: frame.minX+2*fit, y: frame.minY+2*fit,
                width: max(0, frame.width-4*fit), height: max(0, frame.height-12*fit))).addClip()
            image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: opacity)
            context.restoreGState()
        }
        let phase = min(1, max(0, expansion))
        if compactImage == nil {
            drawFace(readingImage, opacity: 1, angle: 0)
        } else {
            // A complementary handoff never blanks the paper at the midpoint.
            // Keep compact type at its native size so enlarged thumbnail glyphs
            // don't dominate the incoming reading layout. Reverse uses the same phase.
            let blend = Self.smooth((phase-0.25)/0.5)
            drawFace(compactImage, opacity: 1-blend, angle: pose.angle, compact: true)
            drawFace(readingImage, opacity: blend, angle: 0)
        }
        context.restoreGState()
        IvoryPaperStyle.edge.setStroke()
        let edge = outline(in: rect.insetBy(dx: 0.75*scale, dy: 0.75*scale),
                           radius: max(0, IvoryPaperStyle.radius*scale-0.75*scale))
        edge.lineWidth = 1.5*scale; edge.stroke()
        IvoryPaperStyle.meta.withAlphaComponent(0.7).setFill()
        let radius = 1.7*scale
        NSBezierPath(ovalIn: NSRect(x: -radius, y: -radius, width: radius*2, height: radius*2)).fill()
        context.restoreGState()
    }
    private static func smooth(_ value: CGFloat) -> CGFloat {
        let t = min(1, max(0, value))
        return t*t*(3-2*t)
    }
    func faceImage() -> NSImage {
        let image = NSImage(size: pose.frame.size)
        image.lockFocus()
        drawPaper(pin: NSPoint(x: pose.pin.x-pose.frame.minX, y: pose.pin.y-pose.frame.minY))
        image.unlockFocus()
        return image
    }
}

/// Same renderer, symmetric timing, and equal full duration in both directions.
/// Interrupted motion keeps the presented pose AND velocity instead of replaying.
@MainActor
final class PaperPreviewFlight {
    private var window: NSPanel?
    private var timer: MotionClock?
    private var sheet: PaperFlightView?
    private var tracks: [SettlingTrack] = []
    private var startedAt: Double = 0
    private var displayedElapsed: Double = 0
    private var activeDuration: Double = 0
    private var opening = true
    private var recordID: UUID?
    private var opacity = SettlingTrack(start: 1, end: 1, duration: 1, symmetric: true)
    var visibleFrame: NSRect? { window?.isVisible == true ? window?.frame : nil }
    var visiblePose: PaperPose? { visibleFrame == nil ? nil : sheet?.pose }

    func cancel() {
        timer?.stop(); timer = nil
        window?.orderOut(nil)
        tracks.removeAll()
    }
    func animate(from: PaperPose, to: PaperPose, readingImage: NSImage?, compactImage: NSImage? = nil,
                 recordID: UUID? = nil, duration: Double, opening: Bool,
                 initialVelocity: NSPoint = .zero, completion: @escaping () -> Void) {
        let interrupted = visiblePose
        let elapsed = CACurrentMediaTime()-startedAt
        let speeds = interrupted == nil ? [initialVelocity.x, initialVelocity.y, 0, 0, 0, 0, 0, 0]
            : tracks.map { $0.sample(displayedElapsed).velocity }
        let startPose = interrupted ?? from
        let phase = interrupted == nil ? (opening ? CGFloat(0) : 1) : sheet?.expansion ?? 0
        let destinationPhase: CGFloat = opening ? 1 : 0
        let remaining: Double
        if interrupted == nil { remaining = duration }
        else if self.opening == opening { remaining = min(duration, max(0.08, activeDuration-elapsed)) }
        else { remaining = max(0.08, duration*sqrt(Double(abs(destinationPhase-phase)))) }
        let currentOpacity = interrupted == nil ? (Motion.reduceMotion && opening ? CGFloat(0) : 1) : window?.alphaValue ?? 1
        opacity = SettlingTrack(start: currentOpacity, end: Motion.reduceMotion && !opening ? 0 : 1,
            velocity: interrupted == nil ? 0 : opacity.sample(displayedElapsed).velocity,
            duration: remaining, symmetric: true)
        timer?.stop()
        let retainFace = interrupted != nil && self.recordID == recordID
        self.recordID = recordID
        self.opening = opening
        activeDuration = remaining
        tracks = zip(startPose.channels + [phase], to.channels + [destinationPhase]).enumerated().map { index, pair in
            SettlingTrack(start: pair.0, end: pair.1, velocity: speeds[index], duration: remaining, symmetric: true)
        }
        let panel: NSPanel
        let face: PaperFlightView
        if let existing = window, let view = sheet { panel = existing; face = view }
        else {
            panel = NSPanel(contentRect: startPose.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.title = "纸签预览过渡"
            panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            face = PaperFlightView(frame: NSRect(origin: .zero, size: startPose.frame.size))
            face.autoresizingMask = [.width, .height]
            panel.contentView = face
            window = panel; sheet = face
        }
        if !retainFace { face.readingImage = readingImage; face.compactImage = compactImage }
        face.expansion = Motion.reduceMotion ? 1 : phase
        face.place(Motion.reduceMotion ? (opening ? to : startPose) : startPose, in: panel)
        panel.ignoresMouseEvents = !opening
        panel.alphaValue = currentOpacity
        panel.orderFrontRegardless()
        startedAt = CACurrentMediaTime(); displayedElapsed = 0
        let tick = MotionClock()
        timer = tick
        tick.start(on: panel) { [weak self, weak panel, weak face] in
            guard let self, let panel, let face else { return }
            let elapsed = CACurrentMediaTime()-self.startedAt
            self.displayedElapsed = elapsed
            if !Motion.reduceMotion {
                face.place(PaperPose(channels: self.tracks.prefix(7).map { $0.sample(elapsed).value }), in: panel)
                face.expansion = self.tracks[7].sample(elapsed).value
            }
            face.needsDisplay = true
            panel.displayIfNeeded(); panel.invalidateShadow()
            panel.alphaValue = min(1, max(0, self.opacity.sample(elapsed).value))
            if elapsed >= remaining {
                self.timer?.stop(); self.timer = nil
                self.window = nil; self.sheet = nil
                completion()
                panel.orderOut(nil)
                self.window = panel; self.sheet = face
                self.tracks.removeAll()
            }
        }
    }
}
