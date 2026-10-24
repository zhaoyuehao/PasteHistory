import Foundation

/// Finite settle with an explicit velocity channel. Retargeting samples this
/// trajectory instead of restarting an ease from rest. Units are points/second
/// (or radians/second for orientation); the endpoint is exact and at rest.
struct SettlingTrack {
    var start: CGFloat
    var end: CGFloat
    var velocity: CGFloat = 0
    var duration: Double

    static func progress(_ fraction: CGFloat) -> CGFloat {
        let t = min(1, max(0, fraction))
        return 1 - pow(1 - t, 3) * (1 + 3 * t)
    }

    func sample(_ elapsed: Double) -> (value: CGFloat, velocity: CGFloat) {
        let t = CGFloat(min(1, max(0, elapsed / max(0.001, duration))))
        let tail = 1 - t
        let value = start + (end - start) * Self.progress(t)
            + velocity * duration * t * pow(tail, 3)
        let speed = (end - start) * 12 * t * tail * tail / duration
            + velocity * tail * tail * (1 - 4 * t)
        return (value, speed)
    }
}
