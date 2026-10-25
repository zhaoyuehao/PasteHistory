import AppKit
import QuartzCore

/// Moves the actual reading window without relaying out its contents. Layout
/// callbacks update the destination; repeated callbacks never restart the spring.
@MainActor
final class PaperPreviewFollow {
    private weak var window: NSWindow?
    private var target = NSPoint.zero
    private var position = NSPoint.zero
    private var velocity = NSPoint.zero
    var currentVelocity: NSPoint { velocity }
    private var timer: Timer?
    private var lastStep: CFTimeInterval = 0

    func move(_ window: NSWindow, to origin: NSPoint) {
        if self.window !== window { cancel() }
        self.window = window
        target = origin
        if Motion.reduceMotion {
            cancel()
            window.setFrameOrigin(origin)
            return
        }
        guard timer == nil, distance(window.frame.origin, origin) > 0.1 else { return }
        position = window.frame.origin
        lastStep = CACurrentMediaTime()
        let tick = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        timer = tick
        RunLoop.main.add(tick, forMode: .common)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        velocity = .zero
        window = nil
    }

    private func distance(_ a: NSPoint, _ b: NSPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func step() {
        guard let window, window.isVisible else { cancel(); return }
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(1.0 / 30, now - lastStep))
        lastStep = now
        let omega = Motion.paperFollowFrequency
        let damping = Motion.paperFollowDamping
        let decay = exp(-damping * omega * dt)
        let damped = omega * sqrt(1 - damping * damping)
        let cosine = cos(damped * dt), sine = sin(damped * dt)
        func advance(_ position: CGFloat, _ speed: inout CGFloat, _ destination: CGFloat) -> CGFloat {
            let offset = position - destination
            let next = destination + decay * (offset * cosine + (speed + damping * omega * offset) / damped * sine)
            speed = decay * (speed * cosine - (omega * omega * offset + damping * omega * speed) / damped * sine)
            return next
        }
        // Keep subpixel state: AppKit rounds the displayed window origin, which
        // otherwise leaves a spring permanently stuck a pixel from its target.
        let origin = NSPoint(x: advance(position.x, &velocity.x, target.x),
                             y: advance(position.y, &velocity.y, target.y))
        position = origin
        // The animator proxy does not animate setFrameOrigin. Direct per-frame
        // placement is supported and gives interruption an actual current origin.
        window.setFrameOrigin(origin)
        if distance(origin, target) < 0.5 && hypot(velocity.x, velocity.y) < 4 {
            window.setFrameOrigin(target)
            cancel()
        }
    }
}
