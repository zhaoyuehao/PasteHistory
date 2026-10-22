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

    /// 类型筛选：与搜索词并列，切换后立刻重查（无需防抖）
    @Published var filter: ClipFilter = .all {
        didSet {
            guard oldValue != filter else { return }
            searchDebounce?.cancel()
            refresh()
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
        backfillFileImageMetadata()
    }

    var databaseURL: URL { syncDatabase.url }
    var count: Int { totalCount }

    // MARK: - 查询（分页）

    func refresh() {
        let (matched, total) = syncDatabase.counts(query: query, filter: filter)
        matchCount = matched
        totalCount = total
        displayed = syncDatabase.list(query: query, filter: filter, limit: pageSize, offset: 0)
    }

    /// 加载下一页时是否已有一次在途请求
    private var loadingMore = false

    /// 滚动接近底部时加载下一页。
    /// 查询放后台再回主线程追加：以前在主线程 `queue.sync` 同步等 DB 队列
    /// （LIKE 无索引全表扫 + 每行 JSON/blob 解码），滚到底那一下正好有
    /// 滚动动画在跑，主线程卡几毫秒就是肉眼可见的顿
    func loadMore() {
        guard !loadingMore, displayed.count < matchCount else { return }
        loadingMore = true
        let query = self.query
        let filter = self.filter
        let offset = displayed.count
        let limit = pageSize
        let database = syncDatabase
        Task.detached(priority: .userInitiated) { [weak self] in
            let next = database.list(query: query, filter: filter, limit: limit, offset: offset)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.loadingMore = false
                guard !next.isEmpty else { return }
                // 去掉可能与当前页重叠的 id（同步导入期间的并发变化）
                let known = Set(self.displayed.map { $0.id })
                self.displayed.append(contentsOf: next.filter { !known.contains($0.id) })
            }
        }
    }

    func recent(_ n: Int) -> [ClipItem] {
        syncDatabase.list(query: "", limit: n, offset: 0)
    }

    // MARK: - 增删（写库 + 触发同步）

    /// 返回是否为新插入（同内容去重命中时为 false）
    @discardableResult
    func upsert(_ item: ClipItem) -> Bool {
        let inserted = syncDatabase.upsert(item)
        refresh()
        if inserted {
            iCloudSync.shared.exportClip(item)
            // .image 和 .files 里的图片文件（如微信复制的 jpg）都做 OCR；其余类型内部直接跳过
            OCRIndexer.shared.indexIfNeeded(item) { [weak self] updated in
                guard let self else { return }
                self.refresh()
                // OCR 文本同步给其他设备，避免重复识别
                iCloudSync.shared.exportClip(updated)
            }
        }
        return inserted
    }

    /// 应用把一次复制拆成多次写剪贴板时用：把后到的图片合并进刚入库的纯文本记录
    @discardableResult
    func attachImage(id: UUID, saved: (name: String, thumbnail: Data?), caption: String?) -> Bool {
        guard var item = syncDatabase.get(id: id), item.kind == .text, item.imageFile == nil else { return false }
        item.kind = .image
        item.imageFile = saved.name
        item.thumbnailData = saved.thumbnail
        if item.text == nil, let caption { item.text = caption }
        syncDatabase.replace(item)
        refresh()
        iCloudSync.shared.exportClip(item)
        OCRIndexer.shared.indexIfNeeded(item) { [weak self] updated in
            self?.refresh()
            iCloudSync.shared.exportClip(updated)
        }
        return true
    }

    /// 同上：把后到的文字合并进刚入库的图片记录
    @discardableResult
    func attachText(id: UUID, text: String) -> Bool {
        guard var item = syncDatabase.get(id: id), item.kind == .image, item.text == nil else { return false }
        item.text = text
        syncDatabase.replace(item)
        refresh()
        iCloudSync.shared.exportClip(item)
        return true
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
        // 置顶时间随记录走：本机排序用它，iCloud 导出也带着它，
        // 其他设备导入后置顶顺序一致
        if item.pinned { item.pinnedAt = Date() }
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

    nonisolated static func makeThumbnail(cg: CGImage, maxPixel: CGFloat = 128) -> Data? {
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

    /// 只查缓存不读盘：展开动画的首帧用它，命中就零延迟
    func peek(named name: String?) -> NSImage? {
        guard let name, !name.isEmpty else { return nil }
        return imageCache.object(forKey: name as NSString)
    }

    /// 同上，按文件路径查缓存
    func peekFile(path: String?) -> NSImage? {
        guard let path, !path.isEmpty else { return nil }
        return imageCache.object(forKey: path as NSString)
    }

    /// 后台解码完成后回填缓存，下一次展开直接命中
    func cache(_ image: NSImage, named name: String?, path: String?) {
        let cost = Int(image.size.width * image.size.height * 4)
        if let name, !name.isEmpty {
            imageCache.setObject(image, forKey: name as NSString, cost: cost)
        }
        if let path, !path.isEmpty {
            imageCache.setObject(image, forKey: path as NSString, cost: cost)
        }
    }

    /// 后台解码（nonisolated，不碰 MainActor），供展开动画预热
    nonisolated static func decodeImage(named name: String?) -> NSImage? {
        guard let name, !name.isEmpty else { return nil }
        return NSImage(contentsOf: imagesDirectoryURL.appendingPathComponent(name))
    }

    nonisolated static func decodeImage(atPath path: String?) -> NSImage? {
        guard let path, !path.isEmpty else { return nil }
        return NSImage(contentsOfFile: path)
    }

    nonisolated static var imagesDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PasteHistory", isDirectory: true)
            .appendingPathComponent("images", isDirectory: true)
    }

    /// 文件类图片的预览图（按路径缓存；微信等来源的图片文件不拷进 images 目录）
    func fileImage(path: String?) -> NSImage? {
        guard let path, !path.isEmpty else { return nil }
        if let cached = imageCache.object(forKey: path as NSString) { return cached }
        guard let img = NSImage(contentsOfFile: path) else { return nil }
        imageCache.setObject(img, forKey: path as NSString,
                             cost: Int(img.size.width * img.size.height * 4))
        return img
    }

    /// 老数据清理：旧版本文本指纹未去首尾空白，同一段文字可能被反复存成多条。
    /// 启动时按新指纹分组，每组保留一条（置顶优先，其次最新），其余连同 iCloud 一起删。
    private func dedupeExistingTextItems() {
        let texts = syncDatabase.all().filter { $0.kind == .text }
        var keeper: [String: ClipItem] = [:]
        var dupes: [UUID] = []
        for item in texts {
            let hash = ClipItem.textContentHash(item.text ?? "")
            if let prev = keeper[hash] {
                // 置顶优先保留；都没置顶则留最新的一条
                let keepNew = item.pinned != prev.pinned ? item.pinned : item.createdAt >= prev.createdAt
                dupes.append(keepNew ? prev.id : item.id)
                if keepNew { keeper[hash] = item }
            } else {
                keeper[hash] = item
            }
        }
        for id in dupes { remove(id: id) }
    }

    /// 老数据回填：图片文件类条目（kind == .files）补缩略图和 OCR，新版本才支持
    private func backfillFileImageMetadata() {
        let targets = syncDatabase.all().filter {
            $0.firstImageFilePath != nil && ($0.thumbnailData == nil || $0.ocrText == nil)
        }
        guard !targets.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            // 缩略图解码放后台，避免启动时解码大图卡 UI
            var thumbs: [UUID: Data] = [:]
            for item in targets where item.thumbnailData == nil {
                if let path = item.firstImageFilePath,
                   let cg = ClipboardMonitor.loadCGImage(atPath: path),
                   let data = ClipStore.makeThumbnail(cg: cg) {
                    thumbs[item.id] = data
                }
            }
            Task { @MainActor in
                guard let self else { return }
                for var item in targets {
                    if let data = thumbs[item.id] {
                        item.thumbnailData = data
                        self.syncDatabase.replace(item)
                    }
                    if item.ocrText == nil {
                        OCRIndexer.shared.indexIfNeeded(item) { [weak self] updated in
                            self?.refresh()
                            iCloudSync.shared.exportClip(updated)
                        }
                    }
                }
                self.refresh()
            }
        }
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
        static let anchorPanel = "anchorPanelToInput"
        static let panelWidth = "panelWidth"
        static let panelHeight = "panelHeight"
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

    /// 面板贴着唤起它的输入框出现（默认开）。
    /// 粘贴的终点永远是输入框，视线已经在那里了，不该再被拉到屏幕中央。
    var anchorPanel: Bool {
        get { defaults.object(forKey: Key.anchorPanel) == nil ? true : defaults.bool(forKey: Key.anchorPanel) }
        set { defaults.set(newValue, forKey: Key.anchorPanel) }
    }

    /// 面板尺寸：用户拖边调整后的选择。未存过（0）→ φ 默认 400×647（与 Theme.Panel 一致）。
    /// 读时夹回可调范围，防外部写入越界
    var panelWidth: CGFloat {
        get { let v = defaults.double(forKey: Key.panelWidth); return v <= 0 ? 400 : min(max(v, 340), 940) }
        set { defaults.set(newValue, forKey: Key.panelWidth) }
    }

    var panelHeight: CGFloat {
        get { let v = defaults.double(forKey: Key.panelHeight); return v <= 0 ? 647 : min(max(v, 360), 1200) }
        set { defaults.set(newValue, forKey: Key.panelHeight) }
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
