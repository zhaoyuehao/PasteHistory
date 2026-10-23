import AppKit

extension ClipFilter {
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

extension ClipItem {
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

    /// 解码后的缩略图缓存：`thumbnailData` 是随记录存储的 PNG blob，
    /// `NSImage(data:)` 每次都是一次解析。以前这里是裸计算属性——
    /// 行每次重渲染都重新解码，按一次方向键 = 可见的图片行各解一遍。
    /// key 里带上 blob 字节数：缩略图更新后字节数几乎必然变化，缓存自动失效
    private static let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 400
        return cache
    }()

    var thumbnail: NSImage? {
        guard let data = thumbnailData else { return nil }
        let key = "\(id.uuidString)-\(data.count)" as NSString
        if let cached = Self.thumbnailCache.object(forKey: key) { return cached }
        guard let image = NSImage(data: data) else { return nil }
        Self.thumbnailCache.setObject(image, forKey: key, cost: data.count)
        return image
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

    /// formatter 按 format string 缓存。DateFormatter 创建是 Foundation 里
    /// 出了名的贵（locale/calendar 全套初始化），以前每行每次渲染都新建一个，
    /// 按住方向键 key repeat 时每秒要新建上百个——这是上下切换卡顿的大头之一
    private static var formatterCache: [String: DateFormatter] = [:]
    private static let formatterLock = NSLock()

    private static func format(_ d: Date, _ f: String) -> String {
        formatterLock.lock()
        let df = formatterCache[f] ?? {
            let made = DateFormatter()
            made.dateFormat = f
            formatterCache[f] = made
            return made
        }()
        formatterLock.unlock()
        return df.string(from: d)
    }
}
