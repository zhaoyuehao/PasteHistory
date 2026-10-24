import Foundation

struct FileMetadata: Sendable {
    let exists: Bool
    let bytes: Int?

    static func read(path: String) async -> FileMetadata {
        await Task.detached(priority: .userInitiated) {
            let exists = FileManager.default.fileExists(atPath: path)
            let bytes = exists ? (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int : nil
            return FileMetadata(exists: exists, bytes: bytes)
        }.value
    }
}
