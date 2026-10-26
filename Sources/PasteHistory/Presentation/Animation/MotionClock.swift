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
        // Setup and initial AppKit drawing are not elapsed animation time.
        // Start on the first delivered display tick; subsequent ticks still use
        // real elapsed time, including missed frames (never clamp to hide stalls).
        previousTime = 0
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
        let delta = previousTime > 0 ? max(0, time-previousTime) : 0
        previousTime = time
        update?(Frame(time: time, delta: delta))
    }
}
