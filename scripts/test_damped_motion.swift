import Foundation

@main
struct DampedMotionChecks {
    static func main() {
        func close(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 1e-8) {
            precondition(abs(a-b) < tolerance, "\(a) != \(b)")
        }
        for anchorTime in [CGFloat(0.020), 0.050] {
            var reference = DampedMotion(values: [158], anchorTime: anchorTime)
            reference.retarget([480]); reference.advance(by: 0.12)
            for hz in [30, 60, 120] {
                var motion = DampedMotion(values: [158], anchorTime: anchorTime)
                motion.retarget([480])
                var elapsed = 0.0
                while elapsed < 0.12 {
                    let dt = min(1/Double(hz), 0.12-elapsed)
                    motion.advance(by: dt); elapsed += dt
                }
                close(motion.values[0], reference.values[0])
                close(motion.states[0].velocity, reference.states[0].velocity)
                close(motion.accelerations[0], reference.accelerations[0])
            }
            let before = reference.states[0], acceleration = reference.accelerations[0]
            reference.retarget([158])
            close(reference.values[0], before.value)
            close(reference.states[0].velocity, before.velocity)
            close(reference.accelerations[0], acceleration)
            var split = reference
            for dt in [0.003, 0.027, 0.016, 0.084, 0.11] { split.advance(by: dt) }
            reference.advance(by: 0.24)
            close(split.values[0], reference.values[0])
            close(split.states[0].velocity, reference.states[0].velocity)
        }
        var motion = DampedMotion(values: [158])
        motion.retarget([480])
        motion.advance(by: 0.12)
        motion.retarget([158])
        var peak: CGFloat = 0
        var turnTime = 0.0
        for tick in 1...240 {
            motion.advance(by: 0.001)
            peak = max(peak, abs(motion.accelerations[0]))
            if turnTime == 0 && motion.states[0].velocity < 0 { turnTime = Double(tick)/1000 }
        }
        precondition(peak < 70_000 && turnTime >= 0.025 && turnTime < 0.05,
                     "A reversal must brake continuously without the previous 175k pt/s² impulse")
        for index in 0..<40 {
            motion.retarget([index.isMultiple(of: 2) ? 480 : 158])
            motion.advance(by: index.isMultiple(of: 3) ? 0.1 : 0.2)
            precondition(motion.values[0].isFinite && motion.values[0] >= 158 && motion.values[0] <= 480)
        }
        motion.retarget([480]); motion.advance(by: 10)
        precondition(motion.isSettled(tolerances: [0.2]))
        close(motion.values[0], 480)
        motion.track([482], delta: 0.02)
        close(motion.states[0].velocity, 100)
        close(motion.accelerations[0], 0)
        motion.retarget([480])
        close(motion.states[0].velocity, 100)
        motion.advance(by: 1)
        precondition(motion.isSettled(tolerances: [0.2]))
        print("PASS: exact 30/60/120 Hz and irregular sampling, continuous x/v/a, bounded reversal, repeated retargets, gesture momentum, long pause")
        print("Reversal peak acceleration: \(peak) pt/s²; direction changes at \(turnTime*1000) ms")
    }
}
