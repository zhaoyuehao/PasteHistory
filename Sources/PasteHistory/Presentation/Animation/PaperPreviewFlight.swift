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

/// The shell changes shape around its pin. Faces keep their original pixel scale
/// and stable text layout; increasing the shell exposes more of the reading face.
final class PaperFlightView: NSView {
    var pose = PaperPose(frame: .zero)
    var source: NSImage?
    var destination: NSImage?
    var mix: CGFloat = 0
    override var isOpaque: Bool { false }

    static func faceRect(image: NSSize, sheet: NSSize) -> NSRect {
        NSRect(x: 0, y: sheet.height-image.height, width: image.width, height: image.height)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        let frame = pose.frame
        context.translateBy(x: pose.pin.x-frame.minX, y: pose.pin.y-frame.minY)
        context.rotate(by: pose.angle)
        context.translateBy(x: -pose.size.width/2, y: pose.inset-pose.size.height)
        drawFace()
        context.restoreGState()
    }
    private func drawFace() {
        NSGraphicsContext.saveGraphicsState()
        let rect = NSRect(origin: .zero, size: pose.size)
        let outline = NSBezierPath(roundedRect: rect, xRadius: IvoryPaperStyle.radius, yRadius: IvoryPaperStyle.radius)
        outline.addClip()
        guard let context = NSGraphicsContext.current?.cgContext else {
            NSGraphicsContext.restoreGraphicsState()
            return
        }
        func paint(_ image: NSImage?, opacity: CGFloat) {
            context.saveGState()
            context.setAlpha(opacity)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            IvoryPaperStyle.fill.setFill()
            rect.fill()
            if let image {
                image.draw(in: Self.faceRect(image: image.size, sheet: pose.size),
                           from: .zero, operation: .sourceOver, fraction: 1)
            }
            context.endTransparencyLayer()
            context.restoreGState()
        }
        paint(source, opacity: 1)
        if destination != nil { paint(destination, opacity: mix) }
        // The hole belongs to the shell, not either face's different text layout.
        // Clear only the interior header strip so the outer edge remains intact.
        let dotScale = pose.inset / IvoryPaperStyle.pinInset
        IvoryPaperStyle.fill.setFill()
        NSRect(x: 1.5, y: rect.height - 10 * dotScale,
               width: max(0, rect.width - 3), height: max(0, 10 * dotScale - 1.5)).fill()
        IvoryPaperStyle.meta.withAlphaComponent(0.7).setFill()
        let radius = 1.7 * dotScale
        NSBezierPath(ovalIn: NSRect(x: rect.midX-radius, y: rect.height-pose.inset-radius,
                                   width: radius*2, height: radius*2)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    func faceImage() -> NSImage {
        let image = NSImage(size: pose.size)
        image.lockFocus()
        drawFace()
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

    func animate(from: PaperPose, to: PaperPose, image: NSImage?, endImage: NSImage?,
                 duration: Double, opening: Bool, initialVelocity: NSPoint = .zero,
                 completion: @escaping () -> Void) {
        let interrupted = visiblePose
        let elapsed = CACurrentMediaTime() - startedAt
        let speeds = interrupted == nil ? [initialVelocity.x, initialVelocity.y, 0, 0, 0, 0, 0]
            : tracks.map { $0.sample(elapsed).velocity }
        let startPose = interrupted ?? from
        let startImage = interrupted == nil ? image : sheet?.faceImage()
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
        face.source = Motion.reduceMotion && opening ? endImage : startImage
        face.destination = Motion.reduceMotion ? nil : endImage
        face.mix = 0
        face.pose = Motion.reduceMotion ? (opening ? to : startPose) : startPose
        panel.setFrame(face.pose.frame, display: false)
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
                    face.pose = PaperPose(channels: self.tracks.map { $0.sample(elapsed).value })
                    panel.setFrame(face.pose.frame, display: false)
                }
                let mix = min(1, max(0, (t - 0.25) / 0.5))
                face.mix = mix * mix * (3 - 2*mix)
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
