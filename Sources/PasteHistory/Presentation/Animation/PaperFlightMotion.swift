import Foundation

/// A single evolving motion state. Complete flights retain the symmetric finite
/// trajectory; changing the target keeps position, velocity, acceleration and the clock.
/// A critically damped third-order response builds braking force continuously,
/// instead of fitting an increasingly short ease to the remaining distance.
struct PaperFlightMotion {
    typealias State = (value: CGFloat, velocity: CGFloat, acceleration: CGFloat)
    private(set) var states: [State]
    private(set) var destination: [CGFloat]
    private(set) var isFinished = false
    private var tracks: [SettlingTrack]
    private var elapsed: Double = 0
    private var duration: Double
    private var retargeting = false
    private var spans: [CGFloat]
    // Screen points, angle, pin inset, padding, expansion, opacity.
    private let tolerances: [CGFloat] = [0.1, 0.1, 0.1, 0.1, 0.0001, 0.002, 0.002, 0.0003, 0.001]

    init(from: [CGFloat], to: [CGFloat], velocities: [CGFloat], duration: Double) {
        precondition(from.count == 9 && to.count == 9 && velocities.count == 9)
        self.duration = duration
        destination = to
        spans = from.indices.map { max(abs(to[$0]-from[$0]), abs(velocities[$0])*duration/1.5) }
        tracks = from.indices.map {
            SettlingTrack(start: from[$0], end: to[$0], velocity: velocities[$0], duration: duration, symmetric: true)
        }
        // Before the first moving frame, there is no acceleration to inherit.
        states = tracks.map { ($0.start, $0.velocity, 0) }
    }

    mutating func retarget(to target: [CGFloat], reducedMotionDuration: Double? = nil) {
        guard target != destination else { return }
        spans = states.indices.map { max(spans[$0], abs(target[$0]-states[$0].value)) }
        destination = target
        isFinished = false
        if let duration = reducedMotionDuration {
            // Accessibility mode only fades; it does not need inertial travel.
            self.duration = duration
            tracks = states.indices.map {
                SettlingTrack(start: states[$0].value, end: target[$0], velocity: states[$0].velocity,
                              duration: duration, symmetric: true)
            }
            elapsed = 0
            retargeting = false
        } else {
            retargeting = true
        }
    }

    mutating func advance(by delta: Double) {
        guard !isFinished, delta > 0 else { return }
        // A wake from sleep should settle, not integrate hours of missed frames
        // on the UI thread. Half a second exceeds this response's settling time.
        let dt = CGFloat(min(0.5, max(0, delta)))
        if retargeting {
            // Smoothly limit requested velocity rather than entering/leaving
            // a hard plateau. Repeated reversals keep braking force continuous;
            // near the endpoint this approaches the critically damped (D+w)^3
            // response without an oscillating tail.
            let steps = max(1, Int(ceil(dt / (1.0/480))))
            let h = dt / CGFloat(steps)
            for _ in 0..<steps {
                states = states.indices.map { index in
                    let limit = max(0.001, spans[index]*1.5/Motion.paperOpenDuration)
                    return Self.integrate(states[index], toward: destination[index], speedLimit: limit, dt: h)
                }
            }
            isFinished = states.indices.allSatisfy {
                let tolerance = tolerances[$0], state = states[$0]
                return abs(state.value-destination[$0]) < tolerance
                    && abs(state.velocity) < tolerance*30
                    && abs(state.acceleration) < tolerance*1500
            }
        } else {
            elapsed += Double(dt)
            states = tracks.map { $0.sample(elapsed) }
            isFinished = elapsed >= duration
        }
        if isFinished { states = destination.map { ($0, 0, 0) } }
    }

    private static func integrate(_ s: State, toward target: CGFloat, speedLimit: CGFloat, dt: CGFloat) -> State {
        let w = Motion.paperRetargetFrequency
        func derivative(_ s: State) -> State {
            let requested = speedLimit * tanh(w*(target-s.value)/(3*speedLimit))
            return (s.velocity, s.acceleration, 3*w*w*(requested-s.velocity)-3*w*s.acceleration)
        }
        func offset(_ s: State, _ d: State, _ h: CGFloat) -> State {
            (s.value+d.value*h, s.velocity+d.velocity*h, s.acceleration+d.acceleration*h)
        }
        // Small RK4 substeps keep the response equivalent at 60/120 Hz and after
        // irregular frames; neither the display clock nor user input is delayed.
        let a = derivative(s)
        let b = derivative(offset(s, a, dt/2))
        let c = derivative(offset(s, b, dt/2))
        let d = derivative(offset(s, c, dt))
        return (s.value+dt*(a.value+2*b.value+2*c.value+d.value)/6,
                s.velocity+dt*(a.velocity+2*b.velocity+2*c.velocity+d.velocity)/6,
                s.acceleration+dt*(a.acceleration+2*b.acceleration+2*c.acceleration+d.acceleration)/6)
    }

}
