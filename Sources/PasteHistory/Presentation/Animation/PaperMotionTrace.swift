import Foundation
import QuartzCore

/// Opt-in callback diagnostics, not compositor FPS. Capture only numeric timing
/// in memory during motion; formatting and one asynchronous write happen at exit.
struct PaperMotionTrace {
    let enabled = ProcessInfo.processInfo.arguments.contains("--trace-paper-motion")
    private struct Sample {
        let arrival: Double
        let delta: Double
        let work: Double
        let window: Double
        let face: Double
        let shadow: Double
        let expansion: CGFloat
    }
    private var samples: [Sample] = []
    private var started = 0.0
    private var opening = true
    private var refreshRate = 60
    private var active = false

    mutating func begin(opening: Bool, refreshRate: Int) {
        guard enabled else { return }
        finish(reason: "retargeted")
        self.opening = opening
        self.refreshRate = refreshRate
        samples.removeAll(keepingCapacity: true)
        samples.reserveCapacity(128)
        started = CACurrentMediaTime()
        active = true
    }
    mutating func record(callbackTime: Double, delta: Double, work: Double,
                         windowWork: Double, faceWork: Double, shadowWork: Double, expansion: CGFloat) {
        guard enabled, active, samples.count < 512 else { return }
        samples.append(Sample(arrival: callbackTime, delta: delta, work: work,
            window: windowWork, face: faceWork, shadow: shadowWork, expansion: expansion))
    }
    mutating func finish(reason: String) {
        guard enabled, active else { return }
        active = false
        let gaps = zip(samples, samples.dropFirst()).map { $1.arrival-$0.arrival }
        let work = samples.map(\.work).sorted()
        let travelFrames = samples.filter { opening ? $0.expansion < 0.95 : $0.expansion > 0.05 }.count
        let p95 = work.isEmpty ? 0 : work[Int(Double(work.count-1)*0.95)]
        var lines = [String(format: "paper-motion pid=%d direction=%@ result=%@ refresh_hz=%d callbacks=%d travel_callbacks=%d first_wait_ms=%.2f max_gap_ms=%.2f p95_cpu_ms=%.2f max_cpu_ms=%.2f",
            ProcessInfo.processInfo.processIdentifier, opening ? "open" : "close", reason, refreshRate,
            samples.count, travelFrames, ((samples.first?.arrival ?? started)-started)*1000,
            (gaps.max() ?? 0)*1000, p95*1000, (work.last ?? 0)*1000)]
        lines.append("elapsed_ms,model_dt_ms,cpu_ms,window_ms,faces_ms,shadow_ms,expansion")
        lines += samples.map {
            String(format: "%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.5f", ($0.arrival-started)*1000,
                $0.delta*1000, $0.work*1000, $0.window*1000, $0.face*1000, $0.shadow*1000, Double($0.expansion))
        }
        MotionTraceLog.write(lines.joined(separator: "\n"))
        samples.removeAll(keepingCapacity: true)
    }
}
