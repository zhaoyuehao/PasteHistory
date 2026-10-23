import AppKit
import QuartzCore

/// A bounded, non-key window tracks the moving sheet. Empty desktop space
/// remains click-through; the visible moving sheet consumes clicks during flight.
@MainActor
final class PaperPreviewFlight {
    private var window: NSPanel?
    private var timer: Timer?
    private var imageView: NSImageView?
    var visibleFrame: NSRect? { window?.isVisible == true ? window?.frame : nil }
    var visibleImage: NSImage? { visibleFrame == nil ? nil : imageView?.image }

    func cancel() {
        timer?.invalidate(); timer = nil
        window?.orderOut(nil)
    }

    func animate(from: NSRect, to: NSRect, image: NSImage?, endImage: NSImage? = nil,
                 duration: Double, opening: Bool, progress: @escaping (CGFloat) -> Void,
                 completion: @escaping () -> Void) {
        cancel()
        let panel = NSPanel(contentRect: from, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = "纸签预览过渡"
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        let host = NSView(frame: NSRect(origin: .zero, size: from.size))
        if opening {
            host.wantsLayer = true
            host.layer?.backgroundColor = IvoryPaperStyle.fill.cgColor
            host.layer?.cornerRadius = IvoryPaperStyle.radius
            host.layer?.borderColor = IvoryPaperStyle.edge.cgColor
            host.layer?.borderWidth = 1.5
        }
        let sheet = NSImageView(frame: host.bounds)
        sheet.image = image
        // Unfold the sheet without stretching its short excerpt into giant text.
        sheet.imageScaling = opening ? .scaleProportionallyDown : .scaleAxesIndependently
        sheet.imageAlignment = opening ? .alignTop : .alignCenter
        sheet.autoresizingMask = [.width, .height]
        host.addSubview(sheet)
        let destination = NSImageView(frame: host.bounds)
        destination.image = endImage; destination.imageScaling = .scaleAxesIndependently
        destination.autoresizingMask = [.width, .height]; destination.alphaValue = 0
        host.addSubview(destination)
        panel.contentView = host
        window = panel; imageView = sheet
        panel.orderFrontRegardless()
        let start = CACurrentMediaTime()
        let tick = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self, weak panel] timer in
            MainActor.assumeIsolated {
            guard let self, let panel else { timer.invalidate(); return }
            let t = min(1, CGFloat((CACurrentMediaTime() - start) / duration))
            let p = Motion.reduceMotion ? t : Motion.paperProgress(t, opening: opening)
            let rect = NSRect(x: from.minX + (to.minX-from.minX)*p,
                              y: from.minY + (to.minY-from.minY)*p,
                              width: from.width + (to.width-from.width)*p,
                              height: from.height + (to.height-from.height)*p)
            panel.setFrame(rect, display: true)
            if opening { panel.alphaValue = 1 - max(0, (t-0.75)/0.25) }
            else if endImage != nil {
                sheet.alphaValue = 1-t; destination.alphaValue = t
                panel.alphaValue = 1 - max(0, (t-0.8)/0.2)
            } else { panel.alphaValue = 1-t }
            progress(t)
            if t >= 1 {
                self.cancel()
                completion()
            }
            }
        }
        timer = tick
        RunLoop.main.add(tick, forMode: .common)
    }
}
