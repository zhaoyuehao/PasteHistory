import Foundation

/// A critically damped spring whose anchor follows the requested destination.
/// r' = (g-r)/tau; x' = v; v' = w²(r-x)-2wv.
/// The exact solution preserves x/v/a on retarget and is independent of frame rate.
struct DampedMotion {
    struct State {
        var value: CGFloat
        var velocity: CGFloat = 0
        var anchor: CGFloat
    }
    private(set) var states: [State]
    private(set) var destination: [CGFloat]
    let frequency: CGFloat
    let anchorRate: CGFloat

    init(values: [CGFloat], velocities: [CGFloat]? = nil,
         frequency: CGFloat = 20, anchorTime: CGFloat = 0.020) {
        precondition(frequency > 0 && anchorTime > 0)
        precondition(velocities == nil || velocities!.count == values.count)
        self.frequency = frequency
        anchorRate = 1 / anchorTime
        destination = values
        states = values.indices.map { State(value: values[$0], velocity: velocities?[$0] ?? 0, anchor: values[$0]) }
    }
    var values: [CGFloat] { states.map(\.value) }
    var accelerations: [CGFloat] {
        states.map { frequency * frequency * ($0.anchor - $0.value) - 2 * frequency * $0.velocity }
    }
    mutating func retarget(_ target: [CGFloat]) {
        precondition(target.count == states.count)
        destination = target
    }
    /// Reconcile native pixel rounding without dropping momentum or force.
    mutating func align(to values: [CGFloat]) {
        precondition(values.count == states.count)
        for i in states.indices {
            states[i].anchor += values[i]-states[i].value
            states[i].value = values[i]
        }
    }
    mutating func advance(by delta: Double) {
        guard delta > 0 && delta.isFinite else { return }
        let dt = CGFloat(delta), w = frequency, l = anchorRate
        let ew = exp(-w * dt), el = exp(-l * dt)
        for i in states.indices {
            let s = states[i], g = destination[i], r = s.anchor - g
            let value: CGFloat, velocity: CGFloat
            if abs(w-l) < 0.000001 {
                let a = s.value-g, b = s.velocity+w*a, c = w*w*r/2
                let p = a+b*dt+c*dt*dt
                value = g+p*ew
                velocity = (b+2*c*dt-w*p)*ew
            } else {
                let c = w*w*r / ((w-l)*(w-l))
                let a = s.value-g-c, b = s.velocity+w*a+l*c
                value = g+(a+b*dt)*ew+c*el
                velocity = (b-w*(a+b*dt))*ew-l*c*el
            }
            states[i] = State(value: value, velocity: velocity, anchor: g+r*el)
        }
    }
    func isSettled(tolerances: [CGFloat]) -> Bool {
        precondition(tolerances.count == states.count)
        return states.indices.allSatisfy {
            let s = states[$0], e = tolerances[$0]
            return abs(s.value-destination[$0]) < e && abs(s.anchor-destination[$0]) < e
                && abs(s.velocity) < e*20
        }
    }
    /// Direct manipulation updates the same state that release/close will inherit.
    mutating func track(_ values: [CGFloat], delta: Double) {
        precondition(values.count == states.count)
        for i in states.indices {
            let v = delta > 0.001 && delta < 0.1 ? (values[i]-states[i].value)/CGFloat(delta) : 0
            states[i] = State(value: values[i], velocity: v, anchor: values[i]+2*v/frequency)
        }
        destination = values
    }
    mutating func finish() {
        states = destination.map { State(value: $0, anchor: $0) }
    }
}
