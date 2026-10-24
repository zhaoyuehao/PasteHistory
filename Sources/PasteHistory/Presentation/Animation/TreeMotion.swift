import Foundation

/// Timing/curves for the tree renderer. No record queries or state mutations.
enum TreeMotion {
    static let entranceDuration: Double = 0.20
    static let entranceFadeDuration: Double = 0.09
    static let entranceRise: CGFloat = 12
    static let pageDuration: Double = 0.28
    static let outgoingDuration: CGFloat = 0.14
    static let incomingDuration: CGFloat = 0.23
    static let pageStagger: CGFloat = 0.006
    static let fadeDuration: CGFloat = 0.15
    static func followBlend(dt: CGFloat) -> CGFloat { 1 - pow(0.62, dt * 60) }
}
