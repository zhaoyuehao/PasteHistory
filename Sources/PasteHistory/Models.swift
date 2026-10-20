import Foundation
import AppKit
import CryptoKit

enum ClipKind: String, Codable, CaseIterable {
    case text
    case image
    case files
}

struct ClipItem: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: ClipKind
    /// 文本内容（kind == .text）
    var text: String?
    /// 图片磁盘文件名（kind == .image），存于 Application Support/PasteHistory/images
    var imageFile: String?
    /// 文件路径列表（kind == .files）
    var filePaths: [String]?
    /// 复制时的前台应用名
    var sourceApp: String?
    var createdAt: Date
    var pinned: Bool
    /// 列表缩略图（小尺寸，随记录存储/同步）
    var thumbnailData: Data?
    /// 图片 OCR 出的文本（用于搜索索引）
    var ocrText: String?

    init(id: UUID = UUID(),
         kind: ClipKind,
         text: String? = nil,
         imageFile: String? = nil,
         filePaths: [String]? = nil,
         sourceApp: String? = nil,
         createdAt: Date = Date(),
         pinned: Bool = false,
         thumbnailData: Data? = nil,
         ocrText: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageFile = imageFile
        self.filePaths = filePaths
        self.sourceApp = sourceApp
        self.createdAt = createdAt
        self.pinned = pinned
        self.thumbnailData = thumbnailData
        self.ocrText = ocrText
    }

    /// 去重用内容指纹：文本按内容 hash，图片按文件 hash 名，文件按路径集合
    var contentHash: String {
        switch kind {
        case .text:
            let digest = SHA256.hash(data: Data((text ?? "").utf8))
            return "t:" + digest.map { String(format: "%02x", $0) }.joined().prefix(32)
        case .image:
            return "i:" + (imageFile ?? UUID().uuidString)
        case .files:
            let joined = (filePaths ?? []).joined(separator: "|")
            let digest = SHA256.hash(data: Data(joined.utf8))
            return "f:" + digest.map { String(format: "%02x", $0) }.joined().prefix(32)
        }
    }

    /// 建库时的全文检索列（小写），搜索走 SQLite LIKE
    func searchText() -> String {
        var parts: [String] = []
        if let t = text { parts.append(t) }
        if let ocr = ocrText, !ocr.isEmpty { parts.append(ocr) }
        if let app = sourceApp { parts.append(app) }
        if let paths = filePaths { parts.append(paths.joined(separator: "\n")) }
        if kind == .image { parts.append("图片 图像 截图 image photo") }
        return parts.joined(separator: "\n").lowercased()
    }

    /// 列表里显示的一行摘要
    var summary: String {
        switch kind {
        case .text:
            let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.replacingOccurrences(of: "\n", with: " ⏎ ")
        case .image:
            let ocr = ocrText?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let ocr, !ocr.isEmpty, ocr.count < 60 {
                return "图片 · \(ocr)"
            }
            if let ocr, !ocr.isEmpty {
                return "图片 · " + String(ocr.prefix(40)) + "…"
            }
            return "图片"
        case .files:
            let names = (filePaths ?? []).map { ($0 as NSString).lastPathComponent }
            if names.count == 1 { return names[0] }
            return "\(names.count) 个文件：" + names.prefix(3).joined(separator: "、")
        }
    }

    var isImage: Bool { kind == .image }

    var thumbnail: NSImage? {
        guard let data = thumbnailData else { return nil }
        return NSImage(data: data)
    }
}

enum RelativeTime {
    static func string(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return "今天 " + format(date, "HH:mm")
        }
        if cal.isDateInYesterday(date) {
            return "昨天 " + format(date, "HH:mm")
        }
        return format(date, "MM-dd HH:mm")
    }

    private static func format(_ d: Date, _ f: String) -> String {
        let df = DateFormatter()
        df.dateFormat = f
        return df.string(from: d)
    }
}
