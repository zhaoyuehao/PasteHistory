import Foundation
import AppKit
import CryptoKit
import UniformTypeIdentifiers

enum ClipKind: String, Codable, CaseIterable {
    case text
    case image
    case files
}

/// 类型筛选：与搜索词并列的独立过滤维度，不参与 search_text 匹配
enum ClipFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case image
    case files
    case pinned

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return L10n.all
        case .text: return L10n.text
        case .image: return L10n.image
        case .files: return L10n.files
        case .pinned: return L10n.pinned
        }
    }
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
    /// 最近一次置顶的时间：置顶区按它倒序——「置顶」是把这条拉到最上面的动作，
    /// 新置顶的排第一，而不是按创建时间混排。老记录 / 老同步文件里没有这个字段，为 nil
    var pinnedAt: Date?
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
         pinnedAt: Date? = nil,
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
        self.pinnedAt = pinnedAt
        self.thumbnailData = thumbnailData
        self.ocrText = ocrText
    }

    /// 去重用内容指纹：文本按「去首尾空白后」的内容 hash，图片按文件 hash 名（附带文字参与指纹），文件按路径集合
    var contentHash: String {
        switch kind {
        case .text:
            return Self.textContentHash(text ?? "")
        case .image:
            let base = "i:" + (imageFile ?? UUID().uuidString)
            // 图文记录：同一张图配不同文字视为不同内容
            guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return base }
            let digest = SHA256.hash(data: Data(t.utf8))
            return base + "+t:" + digest.map { String(format: "%02x", $0) }.joined().prefix(32)
        case .files:
            let joined = (filePaths ?? []).joined(separator: "|")
            let digest = SHA256.hash(data: Data(joined.utf8))
            return "f:" + digest.map { String(format: "%02x", $0) }.joined().prefix(32)
        }
    }

    /// 文本指纹：先去掉首尾空白再 hash，"foo" 和 " foo\n" 视为同一内容
    static func textContentHash(_ text: String) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return "t:" + digest.map { String(format: "%02x", $0) }.joined().prefix(32)
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
            // 图文记录：文字部分是用户复制的本意，优先展示
            if let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                return t.replacingOccurrences(of: "\n", with: " ⏎ ")
            }
            let ocr = ocrText?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let ocr, !ocr.isEmpty, ocr.count < 60 {
                return L10n.imageSummary(ocr)
            }
            if let ocr, !ocr.isEmpty {
                return L10n.imageSummary(String(ocr.prefix(40)) + "…")
            }
            return L10n.image
        case .files:
            let names = (filePaths ?? []).map { ($0 as NSString).lastPathComponent }
            return L10n.fileSummary(count: names.count, names: names)
        }
    }

    var isImage: Bool { kind == .image }

    var thumbnail: NSImage? {
        guard let data = thumbnailData else { return nil }
        return NSImage(data: data)
    }

    /// 文件条目里首个图片文件的路径（用于缩略图 / OCR / 预览）
    /// 微信等应用复制的 jpg 以文件形式进剪贴板，kind 是 .files 但内容其实是图
    var firstImageFilePath: String? {
        guard kind == .files else { return nil }
        return (filePaths ?? []).first { path in
            guard let ut = UTType(filenameExtension: (path as NSString).pathExtension.lowercased()) else { return false }
            return ut.conforms(to: .image)
        }
    }
}

enum RelativeTime {
    static func string(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return L10n.value("刚刚", "剛剛", "Just now") }
        if interval < 3600 { return L10n.minutesAgo(Int(interval / 60)) }
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return L10n.todayAt(format(date, "HH:mm"))
        }
        if cal.isDateInYesterday(date) {
            return L10n.yesterdayAt(format(date, "HH:mm"))
        }
        return format(date, "MM-dd HH:mm")
    }

    private static func format(_ d: Date, _ f: String) -> String {
        let df = DateFormatter()
        df.dateFormat = f
        return df.string(from: d)
    }
}
