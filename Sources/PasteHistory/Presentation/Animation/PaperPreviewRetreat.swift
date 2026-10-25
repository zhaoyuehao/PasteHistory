import AppKit
import QuartzCore

/// Dismiss the LIVE reading surface as one object. Fixed logical bounds keep
/// paragraphs, images, OCR and scroll offsets intact while the window scales.
/// The same tracks reverse on reopen; no snapshot or layout swap at dismissal.
@MainActor
final class PaperPreviewRetreat {
    private var timer: MotionClock?
    private var tracks: [SettlingTrack] = []
    private var startedAt: Double = 0
    private var duration: Double = 0
    private(set) var isActive = false
    private(set) var isClosing = false
    private var restFrame = NSRect.zero
    private var pinInset: CGFloat = 0
    var destinationFrame: NSRect { restFrame }

    func cancel() {
        timer?.stop(); timer = nil
        tracks.removeAll()
        isActive = false
    }

    func animate(_ panel: NSPanel, closing: Bool, inset: CGFloat, target: NSRect? = nil,
                 velocity: NSPoint = .zero, reveal: @escaping (CGFloat) -> Void,
                 completion: @escaping () -> Void) {
        let continuing = isActive
        let elapsed = CACurrentMediaTime() - startedAt
        // Use the last presented geometry and its velocity, not an unseen future
        // sample. The drawing and hit region are the same bounded native window.
        let speeds = continuing ? tracks.map { $0.sample(elapsed).velocity }
            : [velocity.x, velocity.y, 0, 0, 0]
        if !continuing { restFrame = panel.frame; pinInset = inset }
        if let target { restFrame = target }
        let destination = closing && !Motion.reduceMotion
            ? Self.destination(restFrame, inset: pinInset) : restFrame
        let start = [panel.frame.minX, panel.frame.minY, panel.frame.width, panel.frame.height, panel.alphaValue]
        let end = [destination.minX, destination.minY, destination.width, destination.height, closing ? CGFloat(0) : 1]
        timer?.stop()
        // A small retreat is deliberately shorter than a full expansion; this
        // duration is for six percent of scale, not a trip back to thumbnail size.
        duration = Motion.reduceMotion ? 0.1 : Motion.paperRetreatDuration
        tracks = zip(start, end).enumerated().map { index, pair in
            SettlingTrack(start: pair.0, end: pair.1, velocity: speeds[index], duration: duration)
        }
        isActive = true; isClosing = closing
        startedAt = CACurrentMediaTime()
        let tick = MotionClock()
        timer = tick
        tick.start(on: panel) { [weak self, weak panel] in
            MainActor.assumeIsolated {
                guard let self, let panel else { return }
                let elapsed = CACurrentMediaTime() - self.startedAt
                let values = self.tracks.map { $0.sample(elapsed).value }
                // NSScrollView preserves a physical anchor during ancestor
                // resizing, which shifts OCR even with fixed logical bounds.
                // Preserve the current logical offsets around this one resize;
                // user scrolling between frames remains fully interactive.
                let viewports = Self.scrollOffsets(in: panel.contentView)
                panel.setFrame(NSRect(x: values[0], y: values[1], width: values[2], height: values[3]), display: false)
                panel.alphaValue = min(1, max(0, values[4]))
                panel.contentView?.layoutSubtreeIfNeeded()
                for (scroll, origin) in viewports {
                    scroll.contentView.scroll(to: origin)
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
                reveal(Self.sourceVisibility(previewOpacity: panel.alphaValue))
                if elapsed >= self.duration {
                    self.cancel()
                    completion()
                }
            }
        }
    }

    private static func scrollOffsets(in view: NSView?) -> [(NSScrollView, NSPoint)] {
        guard let view else { return [] }
        var offsets: [(NSScrollView, NSPoint)] = []
        if let scroll = view as? NSScrollView { offsets.append((scroll, scroll.contentView.bounds.origin)) }
        return offsets + view.subviews.flatMap { scrollOffsets(in: $0) }
    }

    static func destination(_ frame: NSRect, inset: CGFloat) -> NSRect {
        let scale = Motion.paperRetreatScale
        let pinY = frame.maxY - inset
        return NSRect(x: frame.midX-frame.width*scale/2,
                      y: pinY+(inset-frame.height)*scale,
                      width: frame.width*scale, height: frame.height*scale)
    }

    static func sourceVisibility(previewOpacity: CGFloat) -> CGFloat {
        // Restore the branch paper only after the reading face has receded;
        // readable full-size and thumbnail text must not compete throughout.
        let t = min(1, max(0, (0.3-previewOpacity)/0.3))
        return t*t*(3-2*t)
    }
}
