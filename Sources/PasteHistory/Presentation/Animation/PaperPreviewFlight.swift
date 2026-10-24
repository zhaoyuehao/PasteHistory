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
    var visibleImage: NSImage? {
        guard visibleFrame != nil, let view = window?.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(bitmap)
        return image
    }

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
        // Both faces travel with the same sheet; there is no late full-size popup.
        sheet.imageScaling = .scaleAxesIndependently
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
            let mix = min(1, max(0, opening ? t / 0.12 : (t - 0.82) / 0.18))
            let easedMix = mix * mix * (3 - 2 * mix)
            if endImage != nil {
                sheet.alphaValue = 1 - easedMix
                destination.alphaValue = easedMix
            }
            panel.alphaValue = Motion.reduceMotion ? (opening ? t : 1 - t) : 1
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
