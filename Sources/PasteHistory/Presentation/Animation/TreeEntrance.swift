import AppKit
import QuartzCore

/// One clock moves the owner and its bounded child windows together. Moving
/// the real windows keeps pointer hit areas on the visible papers throughout.
@MainActor
final class TreeEntrance {
    private var timer: Timer?
    private var start = CACurrentMediaTime()
    private var y = SettlingTrack(start: 0, end: 0, duration: 0.2)
    private var opacity = SettlingTrack(start: 0, end: 1, duration: 0.09)
    private(set) var targetOrigin = NSPoint.zero

    func present(_ panel: HistoryPanel, target: NSPoint, from current: NSPoint?) {
        let elapsed = CACurrentMediaTime() - start
        let speed = timer != nil ? y.sample(elapsed).velocity : 0
        let alpha = current == nil ? 0 : panel.treeOpacity
        let alphaSpeed = timer != nil ? opacity.sample(elapsed).velocity : 0
        targetOrigin = target
        y = SettlingTrack(start: current?.y ?? (target.y - (Motion.reduceMotion ? 0 : TreeMotion.entranceRise)),
                          end: target.y, velocity: speed, duration: TreeMotion.entranceDuration)
        opacity = SettlingTrack(start: alpha, end: 1, velocity: alphaSpeed,
                                duration: TreeMotion.entranceFadeDuration)
        animate(panel, duration: TreeMotion.entranceDuration, completion: {})
    }

    func dismiss(_ panel: HistoryPanel, completion: @escaping () -> Void) {
        let elapsed = CACurrentMediaTime() - start
        if timer == nil { targetOrigin = panel.frame.origin }
        let speed = timer != nil ? y.sample(elapsed).velocity : 0
        let alphaSpeed = timer != nil ? opacity.sample(elapsed).velocity : 0
        y = SettlingTrack(start: panel.frame.minY, end: targetOrigin.y, velocity: speed, duration: 0.15)
        opacity = SettlingTrack(start: panel.treeOpacity, end: 0, velocity: alphaSpeed, duration: 0.15)
        animate(panel, duration: 0.15, completion: completion)
    }

    func cancel() { timer?.invalidate(); timer = nil }

    private func animate(_ panel: HistoryPanel, duration: Double, completion: @escaping () -> Void) {
        cancel()
        start = CACurrentMediaTime()
        func apply(_ elapsed: Double) {
            panel.setFrameOrigin(NSPoint(x: self.targetOrigin.x, y: self.y.sample(elapsed).value))
            panel.treeOpacity = min(1, max(0, self.opacity.sample(elapsed).value))
            panel.onPaperLayout?()
        }
        apply(0)
        let tick = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                guard let self, panel != nil else { return }
                let elapsed = CACurrentMediaTime() - self.start
                apply(elapsed)
                if elapsed >= duration { self.cancel(); completion() }
            }
        }
        timer = tick
        RunLoop.main.add(tick, forMode: .common)
    }
}
