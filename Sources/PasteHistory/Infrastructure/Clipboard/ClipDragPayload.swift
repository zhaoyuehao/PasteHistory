import AppKit

/// Drag pasteboards are independent from the system clipboard. External drops
/// advertise copy, while the app's private card type also enables merge drops.
enum ClipDragPayload {
    /// Private drag type used when a history card is dropped onto another
    /// history card. Standard pasteboard representations remain alongside it
    /// so dragging into another app continues to copy the record as before.
    static let mergeType = NSPasteboard.PasteboardType("com.verdent.pastehistory.merge-card")

    static func writersWithMergeType(_ writers: [NSPasteboardWriting], id: UUID) -> [NSPasteboardWriting] {
        writers.map { MergeWriter(base: $0, id: id) }
    }

    private final class MergeWriter: NSObject, NSPasteboardWriting {
        let base: NSPasteboardWriting
        let id: UUID

        init(base: NSPasteboardWriting, id: UUID) {
            self.base = base
            self.id = id
        }

        func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
            base.writableTypes(for: pasteboard) + [mergeType]
        }

        func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
            if type == mergeType { return id.uuidString }
            return base.pasteboardPropertyList(forType: type)
        }
    }

    private static func pruneOldExports(in directory: URL) {
        DispatchQueue.global(qos: .utility).async {
            let manager = FileManager.default
            let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
            let urls = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
            for url in urls where url.pathExtension == "png" {
                if let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate, created < cutoff {
                    try? manager.removeItem(at: url)
                }
            }
        }
    }
    static func writers(for item: ClipItem, imagesDirectory: URL) -> [NSPasteboardWriting]? {
        switch item.kind {
        case .text:
            guard let text = item.text, !text.isEmpty else { return nil }
            let writer = NSPasteboardItem()
            writer.setString(text, forType: .string)
            return [writer]
        case .files:
            let paths = item.filePaths ?? []
            // A multi-file card is atomic: don't silently drop only the surviving files.
            guard !paths.isEmpty, paths.allSatisfy({ FileManager.default.fileExists(atPath: $0) }) else { return nil }
            return paths.map { URL(fileURLWithPath: $0) as NSURL }
        case .image:
            guard let name = item.imageFile,
                  let data = try? Data(contentsOf: imagesDirectory.appendingPathComponent(name)) else { return nil }
            // Export a snapshot so deleting history cannot invalidate an accepted drop.
            // System temporary storage remains available to asynchronous receivers.
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PasteHistory-Drag", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                Self.pruneOldExports(in: directory)
                let url = directory.appendingPathComponent(UUID().uuidString + ".png")
                try data.write(to: url, options: .atomic)
                let writer = NSPasteboardItem()
                writer.setString(url.absoluteString, forType: .fileURL)
                writer.setData(data, forType: .png)
                if let text = item.text, !text.isEmpty { writer.setString(text, forType: .string) }
                return [writer]
            } catch { return nil }
        }
    }
}
