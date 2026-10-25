import Foundation

/// Finite settle with an explicit velocity channel. Retargeting samples this
/// trajectory instead of restarting an ease from rest. Units are points/second
/// (or radians/second for orientation); the endpoint is exact and at rest.
struct SettlingTrack {
    var start: CGFloat
    var end: CGFloat
    var velocity: CGFloat = 0
    var duration: Double
    var symmetric = false

    static func progress(_ fraction: CGFloat) -> CGFloat {
        let t = min(1, max(0, fraction))
        return 1 - pow(1 - t, 3) * (1 + 3 * t)
    }

    func sample(_ elapsed: Double) -> (value: CGFloat, velocity: CGFloat, acceleration: CGFloat) {
        let t = CGFloat(min(1, max(0, elapsed / max(0.001, duration))))
        let tail = 1 - t
        // Cubic ease-in/out keeps zero endpoint velocity and time symmetry,
        // but spreads travel more evenly than quintic (peak 1.5 vs 1.875).
        let progress = symmetric ? t*t*(3-2*t) : Self.progress(t)
        let slope = symmetric ? 6*t*tail : 12*t*tail*tail
        let value = start + (end - start) * progress
            + velocity * duration * t * pow(tail, 3)
        let speed = (end - start) * slope / duration
            + velocity * tail * tail * (1 - 4 * t)
        let curvature = symmetric ? 6-12*t : 12*tail*(1-3*t)
        let acceleration = (end-start)*curvature/(duration*duration)
            - 6*velocity*tail*(1-2*t)/duration
        return (value, speed, t >= 1 ? 0 : acceleration)
    }
}
