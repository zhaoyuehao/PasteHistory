import AppKit
import QuartzCore

/// Drive native window motion on the display's cadence, including ProMotion.
/// A fixed 60 Hz timer drifts relative to presentation even with cheap drawing.
@MainActor
final class MotionClock: NSObject {
    private var link: CADisplayLink?
    struct Frame {
        let time: Double
        let delta: Double
    }
    private var previousTime = 0.0
    private var update: ((Frame) -> Void)?
    func start(on window: NSWindow, update: @escaping (Frame) -> Void) {
        stop()
        self.update = update
        previousTime = CACurrentMediaTime()
        let link = window.displayLink(target: self, selector: #selector(step))
        self.link = link
        link.add(to: .main, forMode: .common)
    }
    func stop() {
        link?.invalidate(); link = nil
        update = nil
    }
    @objc private func step(_ sender: CADisplayLink) {
        let time = sender.targetTimestamp > 0 ? sender.targetTimestamp : CACurrentMediaTime()
        let delta = max(0, time-previousTime)
        previousTime = time
        update?(Frame(time: time, delta: delta))
    }
}
