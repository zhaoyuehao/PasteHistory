import Foundation

enum AnchorTrace {
    /// 真机验收只有日志能说清「没贴过去」到底是没拿到输入框还是位置算错，
    /// 所以默认就落盘（一次一行，超过 200KB 就整体重写，不会无限涨）。
    private static let traceURL: URL? = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PasteHistory")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("anchor_trace.log")
    }()

    static func write(_ line: String) {
        guard let url = Self.traceURL else { return }
        let row = Data(String(format: "%.3f %@\n", Date().timeIntervalSince1970, line).utf8)
        let fm = FileManager.default
        let tooBig = ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0 > 200_000
        if !tooBig, let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(row)
            try? handle.close()
        } else {
            try? row.write(to: url)
        }
        if ProcessInfo.processInfo.arguments.contains("--trace-anchor") {
            NSLog("[PH] anchor: %@", line)
        }
    }

}
