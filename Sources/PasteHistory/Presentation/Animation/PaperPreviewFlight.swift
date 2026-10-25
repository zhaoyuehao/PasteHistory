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
        if compactImage == nil {
            drawFace(readingImage, opacity: 1, angle: 0)
        } else {
            // Keep the reading viewport throughout the large part of the flight.
            // Exchange layouts only within 40% of the compact dimensions, also
            // when returning from a magnified preview. Both directions use the
            // same geometric threshold; no middle-of-flight double typography.
            let compact = compactImage!.size
            let relativeSize = max(pose.size.width / max(1, compact.width),
                                   pose.size.height / max(1, compact.height))
            let blend = Self.smooth((relativeSize-1) / 0.4)
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

/// One window and one display clock for the entire interaction, including
/// reversals. A new input changes the motion target and replaces completion;
/// it never restarts the display link or queues the previous destination.
@MainActor
final class PaperPreviewFlight {
    private var window: NSPanel?
    private var timer: MotionClock?
    private var sheet: PaperFlightView?
    private var motion: PaperFlightMotion?
    private var lastFrameTime: Double?
    private var completion: (() -> Void)?
    private var recordID: UUID?
    private var reducedMotion = false
    var visibleFrame: NSRect? { window?.isVisible == true ? window?.frame : nil }
    var visiblePose: PaperPose? { visibleFrame == nil ? nil : sheet?.pose }

    func isDisplaying(record id: UUID?) -> Bool { visiblePose != nil && recordID == id }
    func isTargeting(_ pose: PaperPose, record id: UUID?) -> Bool {
        guard isDisplaying(record: id), let motion else { return false }
        let target = PaperPose(channels: Array(motion.destination.prefix(7)))
        // AppKit rounds native window placement. Ignore that rounding, but not
        // a source pin that becomes available/moves after the selection update.
        return abs(target.pin.x-pose.pin.x) < 1 && abs(target.pin.y-pose.pin.y) < 1
            && abs(target.size.width-pose.size.width) < 1 && abs(target.size.height-pose.size.height) < 1
            && abs(target.inset-pose.inset) < 0.002
    }

    func cancel() {
        timer?.stop(); timer = nil
        window?.orderOut(nil)
        motion = nil; completion = nil; lastFrameTime = nil
    }
    func animate(from: PaperPose, to: PaperPose, readingImage: NSImage?, compactImage: NSImage? = nil,
                 recordID: UUID? = nil, duration: Double, opening: Bool,
                 initialVelocity: NSPoint = .zero, onReady: () -> Void = {}, completion: @escaping () -> Void) {
        let reduce = Motion.reduceMotion
        let target = to.channels + [opening ? 1 : 0, reduce && !opening ? 0 : 1]
        if visiblePose != nil, motion != nil, let panel = window, let face = sheet {
            // The displayed pose and velocity are owned by motion.
            // Do not resample wall time, prepare a new first frame, or restart a
            // clock when the user reverses a sheet that is already on screen.
            motion?.retarget(to: target, reducedMotionDuration: reduce ? duration : nil)
            self.completion = completion
            if self.recordID != recordID {
                face.readingImage = readingImage; face.compactImage = compactImage
            }
            self.recordID = recordID
            panel.ignoresMouseEvents = !opening
            onReady()
            return
        }
        self.recordID = recordID
        self.completion = completion
        reducedMotion = reduce
        let phase: CGFloat = opening ? 0 : 1
        let opacity: CGFloat = reduce && opening ? 0 : 1
        motion = PaperFlightMotion(from: from.channels + [phase, opacity], to: target,
            velocities: [initialVelocity.x, initialVelocity.y, 0, 0, 0, 0, 0, 0, 0], duration: duration, reducedMotion: reduce)
        let panel: NSPanel
        let face: PaperFlightView
        if let existing = window, let view = sheet { panel = existing; face = view }
        else {
            panel = NSPanel(contentRect: from.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.title = "纸签预览过渡"
            panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            face = PaperFlightView(frame: NSRect(origin: .zero, size: from.frame.size))
            face.autoresizingMask = [.width, .height]
            panel.contentView = face
            window = panel; sheet = face
        }
        face.readingImage = readingImage; face.compactImage = compactImage
        face.expansion = reduce ? 1 : phase
        face.place(reduce && opening ? to : from, in: panel)
        panel.ignoresMouseEvents = !opening
        panel.alphaValue = opacity
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        panel.invalidateShadow()
        onReady()
        lastFrameTime = CACurrentMediaTime()
        let tick = MotionClock()
        timer = tick
        tick.start(on: panel) { [weak self] timestamp in self?.step(at: timestamp) }
    }

    private func step(at timestamp: CFTimeInterval) {
        guard let panel = window, let face = sheet, motion != nil else { return }
        let now = timestamp
        // Only a new flight establishes time zero; retargeting leaves this clock alone.
        let delta = lastFrameTime.map { now-$0 } ?? 0
        lastFrameTime = now
        motion?.advance(by: delta)
        guard let motion else { return }
        if !reducedMotion {
            face.place(PaperPose(channels: motion.states.prefix(7).map(\.value)), in: panel)
            face.expansion = motion.states[7].value
        }
        face.needsDisplay = true
        panel.displayIfNeeded(); panel.invalidateShadow()
        panel.alphaValue = min(1, max(0, motion.states[8].value))
        if motion.isFinished {
            timer?.stop(); timer = nil
            let finish = completion
            self.motion = nil; completion = nil; lastFrameTime = nil
            window = nil; sheet = nil
            finish?()
            panel.orderOut(nil)
            window = panel; sheet = face
        }
    }
}
