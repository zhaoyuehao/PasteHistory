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

/// A single reading face is clipped by the moving shell. Text stays upright at
/// its reading scale; rotating rasterized glyphs or blending two layouts shimmers.
final class PaperFlightView: NSView {
    var pose = PaperPose(frame: .zero)
    var readingImage: NSImage?
    private var canvasOrigin: NSPoint?
    override var isOpaque: Bool { false }

    func place(_ pose: PaperPose, in panel: NSPanel) {
        self.pose = pose
        // macOS rounds window origins. Enclose the fractional shell, then draw
        // relative to the ACTUAL origin so the screen-space pin never jumps.
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
            let rotation = AffineTransform(rotationByRadians: pose.angle)
            path.transform(using: rotation)
            return path
        }
        let paper = outline(in: rect, radius: IvoryPaperStyle.radius * scale)
        IvoryPaperStyle.fill.setFill()
        paper.fill()
        context.saveGState()
        paper.addClip()
        if let image = readingImage {
            // Snapshot edges/hole belong to the shell, not the reading layout.
            // Clip those out, then reveal this ONE face without reflow or rotation.
            let imageRect = NSRect(x: rect.minX, y: rect.maxY-image.size.height,
                                   width: image.size.width, height: image.size.height)
            NSBezierPath(rect: NSRect(x: imageRect.minX+2*scale, y: imageRect.minY+2*scale,
                width: max(0, imageRect.width-4*scale), height: max(0, imageRect.height-12*scale))).addClip()
            image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)
        }
        context.restoreGState()
        IvoryPaperStyle.edge.setStroke()
        let edge = outline(in: rect.insetBy(dx: 0.75*scale, dy: 0.75*scale),
                           radius: max(0, IvoryPaperStyle.radius*scale - 0.75*scale))
        edge.lineWidth = 1.5*scale
        edge.stroke()
        IvoryPaperStyle.meta.withAlphaComponent(0.7).setFill()
        let radius = 1.7 * scale
        NSBezierPath(ovalIn: NSRect(x: -radius, y: -radius, width: radius*2, height: radius*2)).fill()
        context.restoreGState()
    }

    func faceImage() -> NSImage {
        let image = NSImage(size: pose.frame.size)
        image.lockFocus()
        drawPaper(pin: NSPoint(x: pose.pin.x-pose.frame.minX, y: pose.pin.y-pose.frame.minY))
        image.unlockFocus()
        return image
    }
}

/// One replaceable trajectory for translation, size and rotation. Mid-flight
/// retargets preserve both pose and velocity; no queued completions or window swap.
@MainActor
final class PaperPreviewFlight {
    private var window: NSPanel?
    private var timer: Timer?
    private var sheet: PaperFlightView?
    private var tracks: [SettlingTrack] = []
    private var startedAt: Double = 0
    private var activeDuration: Double = 0
    private var opening = true
    var visibleFrame: NSRect? { window?.isVisible == true ? window?.frame : nil }
    var visiblePose: PaperPose? { visibleFrame == nil ? nil : sheet?.pose }

    func cancel() {
        timer?.invalidate(); timer = nil
        window?.orderOut(nil)
        tracks.removeAll()
    }

    func animate(from: PaperPose, to: PaperPose, readingImage: NSImage?,
                 duration: Double, opening: Bool, initialVelocity: NSPoint = .zero,
                 completion: @escaping () -> Void) {
        let interrupted = visiblePose
        let elapsed = CACurrentMediaTime() - startedAt
        let speeds = interrupted == nil ? [initialVelocity.x, initialVelocity.y, 0, 0, 0, 0, 0]
            : tracks.map { $0.sample(elapsed).velocity }
        let startPose = interrupted ?? from
        // A reversal keeps the current reading layout. Reopening/selection may
        // replace the record, but never composites old and new text together.
        let content = interrupted != nil && !opening ? sheet?.readingImage : readingImage
        // Updating the selected record doesn't replay a full unfold. Reversing
        // open/close has its own duration, starting with the current momentum.
        let remaining = interrupted != nil && self.opening == opening
            ? min(duration, max(0.08, activeDuration-elapsed)) : duration
        timer?.invalidate()
        self.opening = opening
        activeDuration = remaining
        tracks = zip(startPose.channels, to.channels).enumerated().map { index, pair in
            SettlingTrack(start: pair.0, end: pair.1, velocity: speeds[index], duration: remaining)
        }
        let panel: NSPanel
        let face: PaperFlightView
        if let existing = window, let view = sheet {
            panel = existing; face = view
        } else {
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
        face.readingImage = content
        face.place(Motion.reduceMotion ? (opening ? to : startPose) : startPose, in: panel)
        panel.alphaValue = Motion.reduceMotion && interrupted == nil && opening ? 0 : 1
        face.needsDisplay = true
        panel.orderFrontRegardless()
        startedAt = CACurrentMediaTime()
        let tick = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self, weak panel, weak face] _ in
            MainActor.assumeIsolated {
                guard let self, let panel, let face else { return }
                let elapsed = CACurrentMediaTime() - self.startedAt
                let t = min(1, CGFloat(elapsed / remaining))
                if !Motion.reduceMotion {
                    face.place(PaperPose(channels: self.tracks.map { $0.sample(elapsed).value }), in: panel)
                }
                face.needsDisplay = true
                panel.displayIfNeeded()
                panel.invalidateShadow()
                if Motion.reduceMotion { panel.alphaValue = opening ? t : 1-t }
                if t >= 1 {
                    self.timer?.invalidate(); self.timer = nil
                    // Show the live sheet before removing its identical final face.
                    // followPaper() must see the flight as completed at this point.
                    self.window = nil; self.sheet = nil
                    completion()
                    panel.orderOut(nil)
                    self.window = panel; self.sheet = face
                    self.tracks.removeAll()
                }
            }
        }
        timer = tick
        RunLoop.main.add(tick, forMode: .common)
    }
}
