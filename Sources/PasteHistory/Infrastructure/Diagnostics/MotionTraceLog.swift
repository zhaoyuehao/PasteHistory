import Foundation

/// Bounded, opt-in motion timing log. No record contents, IDs or images. All
/// filesystem work stays off the main thread and outside the animation callback.
enum MotionTraceLog {
    private static let queue = DispatchQueue(label: "com.verdent.pastehistory.motion-trace", qos: .utility)

    static func write(_ timing: String) {
        queue.async {
            let directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/PasteHistory")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("paper_motion.log")
            let data = Data(("\(Date().timeIntervalSince1970)\n" + timing + "\n").utf8)
            let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
            if size + data.count <= 512_000, let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } catch { return }
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
