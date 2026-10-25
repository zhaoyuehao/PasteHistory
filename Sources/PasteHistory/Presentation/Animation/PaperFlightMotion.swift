import Foundation
import SwiftUI

/// One native, non-bouncing spring for resting flights and every interruption.
/// A new target preserves the presented position and velocity. Acceleration is
/// deliberately allowed to change: the new input must apply braking immediately.
/// Unlike a finite ease plus a separate reversal solver, the motion never changes
/// character part way through an interaction, and has no distance-based deadline.
struct PaperFlightMotion {
    typealias State = (value: CGFloat, velocity: CGFloat)
    private(set) var states: [State]
    private(set) var destination: [CGFloat]
    private(set) var isFinished = false
    private let spring: Spring
    private var fadeTracks: [SettlingTrack]?
    private var fadeElapsed = 0.0
    private var fadeDuration = 0.0
    // Below half a backing pixel at 2x, including when the whole card is zoomed.
    // The velocity bound prevents finishing while it is still visibly moving.
    private let tolerances: [CGFloat] = [0.24, 0.24, 0.24, 0.24, 0.0001, 0.002, 0.002, 0.001, 0.001]

    init(from: [CGFloat], to: [CGFloat], velocities: [CGFloat], duration: Double,
         reducedMotion: Bool = false) {
        precondition(from.count == 9 && to.count == 9 && velocities.count == 9)
        spring = Spring(duration: duration, bounce: 0)
        destination = to
        states = zip(from, velocities).map { ($0, $1) }
        if reducedMotion { startFade(duration: duration) }
    }

    mutating func retarget(to target: [CGFloat], reducedMotionDuration: Double? = nil) {
        precondition(target.count == states.count)
        guard target != destination else { return }
        destination = target
        isFinished = false
        if let duration = reducedMotionDuration { startFade(duration: duration) }
    }

    private mutating func startFade(duration: Double) {
        fadeDuration = duration
        fadeElapsed = 0
        fadeTracks = states.indices.map {
            SettlingTrack(start: states[$0].value, end: destination[$0],
                          velocity: states[$0].velocity, duration: duration, symmetric: true)
        }
    }

    mutating func advance(by delta: Double) {
        guard !isFinished, delta > 0 else { return }
        if let tracks = fadeTracks {
            fadeElapsed += delta
            states = tracks.map { let s = $0.sample(fadeElapsed); return (s.value, s.velocity) }
            isFinished = fadeElapsed >= fadeDuration
        } else {
            // Apple's analytic solution, not a frame-rate-dependent numerical
            // integrator. A long frame or wake from sleep needs no catch-up loop.
            states = states.indices.map { index in
                var value = Double(states[index].value)
                var velocity = Double(states[index].velocity)
                spring.update(value: &value, velocity: &velocity,
                              target: Double(destination[index]), deltaTime: delta)
                return (CGFloat(value), CGFloat(velocity))
            }
            isFinished = states.indices.allSatisfy {
                abs(states[$0].value-destination[$0]) < tolerances[$0]
                    && abs(states[$0].velocity) < tolerances[$0]*24
            }
        }
        if isFinished { states = destination.map { ($0, 0) } }
    }
}
