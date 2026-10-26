import AppKit
import QuartzCore

/// Drive native window motion on the display's cadence, including ProMotion.
/// A fixed 60 Hz timer drifts relative to presentation even with cheap drawing.
@MainActor
final class MotionClock: NSObject {
    private var link: CADisplayLink?
    private var update: (() -> Void)?
    func start(on window: NSWindow, update: @escaping () -> Void) {
        stop()
        self.update = update
        let link = window.displayLink(target: self, selector: #selector(step))
        self.link = link
        link.add(to: .main, forMode: .common)
    }
    func stop() {
        link?.invalidate(); link = nil
        update = nil
    }
    @objc private func step(_ sender: CADisplayLink) { update?() }
}
