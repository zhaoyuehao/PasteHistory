import AppKit
import QuartzCore

/// Only the short boundary return is animated. Live pinching follows fingers.
@MainActor
final class PaperScaleReturn {
    private var timer: Timer?
    func cancel() { timer?.invalidate(); timer = nil }
    func settle(from: CGFloat, to: CGFloat, update: @escaping (CGFloat) -> Void) {
        cancel()
        guard abs(from - to) > 0.001, !Motion.reduceMotion else { update(to); return }
        let start = CACurrentMediaTime()
        let tick = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let fraction = min(1, CGFloat((CACurrentMediaTime() - start) / Motion.paperScaleReturnDuration))
                update(from + (to - from) * Motion.paperProgress(fraction, opening: false))
                if fraction >= 1 { self.cancel() }
            }
        }
        timer = tick
        RunLoop.main.add(tick, forMode: .common)
    }
}
