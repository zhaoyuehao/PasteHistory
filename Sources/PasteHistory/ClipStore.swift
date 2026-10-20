import Foundation
import AppKit

/// 剪贴板历史门面：数据全在 SQLite，内存里只有当前展示页 + 图片缓存
@MainActor
final class ClipStore: ObservableObject {
    static let shared = ClipStore()

    /// 当前展示的记录（分页加载）
    @Published private(set) var displayed: [ClipItem] = []
    /// 当前搜索条件下命中的总数
    @Published private(set) var matchCount = 0
    @Published private(set) var totalCount = 0

    @Published var query: String = "" {
        didSet {
            guard oldValue != query else { return }
            searchDebounce?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                Task { @MainActor in self.refresh() }
            }
            searchDebounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }

    let syncDatabase: HistoryDatabase
    private let fm = FileManager.default
    private let imagesDir: URL
    private let imageCache = NSCache<NSString, NSImage>()
    private var searchDebounce: DispatchWorkItem?
    private let pageSize = 60

    private init() {
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let baseDir = appSupport.appendingPathComponent("PasteHistory", isDirectory: true)
        imagesDir = baseDir.appendingPathComponent("images", isDirectory: true)
        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        syncDatabase = HistoryDatabase(url: baseDir.appendingPathComponent("history.sqlite"))
        imageCache.countLimit = 80
        imageCache.totalCostLimit = 120 * 1024 * 1024
        refresh()
    }

    var databaseURL: URL { syncDatabase.url }
    var count: Int { totalCount }

    // MARK: - 查询（分页）

    func refresh() {
        let (matched, total) = syncDatabase.counts(query: query)
        matchCount = matched
        totalCount = total
        displayed = syncDatabase.list(query: query, limit: pageSize, offset: 0)
    }

    /// 滚动接近底部时加载下一页
    func loadMore() {
        guard displayed.count < matchCount else { return }
        let next = syncDatabase.list(query: query, limit: pageSize, offset: displayed.count)
        guard !next.isEmpty else { return }
        // 去掉可能与当前页重叠的 id（同步导入期间的并发变化）
        let known = Set(displayed.map { $0.id })
        displayed.append(contentsOf: next.filter { !known.contains($0.id) })
    }

    func recent(_ n: Int) -> [ClipItem] {
        syncDatabase.list(query: "", limit: n, offset: 0)
    }

    // MARK: - 增删（写库 + 触发同步）

    func upsert(_ item: ClipItem) {
        let inserted = syncDatabase.upsert(item)
        refresh()
        if inserted {
            iCloudSync.shared.exportClip(item)
            if item.kind == .image {
                OCRIndexer.shared.indexIfNeeded(item) { [weak self] updated in
                    guard let self else { return }
                    self.refresh()
                    // OCR 文本同步给其他设备，避免重复识别
                    iCloudSync.shared.exportClip(updated)
                }
            }
        }
    }

    func remove(id: UUID) {
        let item = syncDatabase.get(id: id)
        syncDatabase.delete(id: id)
        if let f = item?.imageFile { deleteImageFile(f) }
        refresh()
        iCloudSync.shared.exportDelete(id: id)
    }

    func clearAll() {
        let victims = syncDatabase.all()
        for item in victims where item.imageFile != nil {
            deleteImageFile(item.imageFile)
        }
        syncDatabase.clearAll()
        refresh()
        iCloudSync.shared.exportClearAll()
    }

    func togglePin(id: UUID) {
        guard var item = syncDatabase.get(id: id) else { return }
        item.pinned.toggle()
        syncDatabase.setPinned(id: id, pinned: item.pinned)
        refresh()
        iCloudSync.shared.exportClip(item)
    }

    /// iCloud 导入后调用
    func reloadFromSync() {
        refresh()
    }

    // MARK: - 图片

    /// 存原图（内容 hash 命名去重）+ 生成小缩略图（进 DB，列表渲染不加载原图）
    func saveImage(_ image: NSImage) -> (name: String, thumbnail: Data?)? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        if data.count > 20 * 1024 * 1024 { return nil } // 超 20MB 不落盘

        let digest = SHA256Hex(data)
        let name = digest + ".png"
        let url = imagesDir.appendingPathComponent(name)
        if !fm.fileExists(atPath: url.path) {
            do { try data.write(to: url) } catch { return nil }
        }
        return (name, Self.makeThumbnail(cg: cg))
    }

    static func makeThumbnail(cg: CGImage, maxPixel: CGFloat = 128) -> Data? {
        let scale = min(1, maxPixel / max(CGFloat(cg.width), CGFloat(cg.height)))
        let w = max(1, Int(CGFloat(cg.width) * scale))
        let h = max(1, Int(CGFloat(cg.height) * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .png, properties: [:])
    }

    func image(named name: String?) -> NSImage? {
        guard let name, !name.isEmpty else { return nil }
        if let cached = imageCache.object(forKey: name as NSString) { return cached }
        let url = imagesDir.appendingPathComponent(name)
        guard let img = NSImage(contentsOf: url) else { return nil }
        imageCache.setObject(img, forKey: name as NSString,
                             cost: Int(img.size.width * img.size.height * 4))
        return img
    }

    var imagesDirectory: URL { imagesDir }

    /// 同步导入时：从 iCloud 日志目录把缺的图片拷到本地
    func importImage(from source: URL, name: String) {
        let dst = imagesDir.appendingPathComponent(name)
        guard !fm.fileExists(atPath: dst.path) else { return }
        try? fm.copyItem(at: source, to: dst)
    }

    func deleteImageFile(_ name: String?) {
        guard let name else { return }
        try? fm.removeItem(at: imagesDir.appendingPathComponent(name))
        imageCache.removeObject(forKey: name as NSString)
    }
}

import CryptoKit

private func SHA256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

// MARK: - 设置

final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let maxItems = "maxItems"
        static let paused = "paused"
        static let pasteAsPlainText = "pasteAsPlainText"
        static let hotKeyEnabled = "hotKeyEnabled"
        static let autoPaste = "autoPaste"
        static let launchedBefore = "launchedBefore"
        static let ignoredApps = "ignoredApps"
        static let iCloudSync = "iCloudSyncEnabled"
        static let iCloudInitialExport = "iCloudInitialExportDone"
        static let machineId = "syncMachineId"
    }

    var maxItems: Int {
        get { let v = defaults.integer(forKey: Key.maxItems); return v <= 0 ? 500 : v }
        set { defaults.set(newValue, forKey: Key.maxItems) }
    }

    var paused: Bool {
        get { defaults.bool(forKey: Key.paused) }
        set { defaults.set(newValue, forKey: Key.paused) }
    }

    var pasteAsPlainText: Bool {
        get { defaults.object(forKey: Key.pasteAsPlainText) == nil ? true : defaults.bool(forKey: Key.pasteAsPlainText) }
        set { defaults.set(newValue, forKey: Key.pasteAsPlainText) }
    }

    var autoPaste: Bool {
        get { defaults.object(forKey: Key.autoPaste) == nil ? true : defaults.bool(forKey: Key.autoPaste) }
        set { defaults.set(newValue, forKey: Key.autoPaste) }
    }

    var hotKeyEnabled: Bool {
        get { defaults.object(forKey: Key.hotKeyEnabled) == nil ? true : defaults.bool(forKey: Key.hotKeyEnabled) }
        set { defaults.set(newValue, forKey: Key.hotKeyEnabled) }
    }

    var launchedBefore: Bool {
        get { defaults.bool(forKey: Key.launchedBefore) }
        set { defaults.set(true, forKey: Key.launchedBefore) }
    }

    /// iCloud 同步开关（默认开；未登录 iCloud Drive 时自动无效）
    var iCloudSync: Bool {
        get { defaults.object(forKey: Key.iCloudSync) == nil ? true : defaults.bool(forKey: Key.iCloudSync) }
        set { defaults.set(newValue, forKey: Key.iCloudSync) }
    }

    var iCloudInitialExportDone: Bool {
        get { defaults.bool(forKey: Key.iCloudInitialExport) }
        set { defaults.set(newValue, forKey: Key.iCloudInitialExport) }
    }

    /// 本机稳定标识，避免把 iCloud 里自己导出的记录再导入一遍
    var machineId: String {
        if let existing = defaults.string(forKey: Key.machineId) { return existing }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: Key.machineId)
        return fresh
    }

    var ignoredApps: [String] {
        get { defaults.stringArray(forKey: Key.ignoredApps) ?? defaultIgnoredApps }
        set { defaults.set(newValue, forKey: Key.ignoredApps) }
    }

    let defaultIgnoredApps = [
        "com.agilebits.onepassword",
        "com.1password.1password",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.apple.keychainaccess",
    ]

    func isIgnored(bundleIdentifier: String?) -> Bool {
        guard let id = bundleIdentifier else { return false }
        return ignoredApps.contains(id)
    }
}
