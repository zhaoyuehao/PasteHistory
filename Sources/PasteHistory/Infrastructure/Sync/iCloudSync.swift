import Foundation
import AppKit

/// iCloud 同步：记录以"一记录一文件"写入 iCloud Drive（com~apple~CloudDocs），
/// 文件名确定性（clips/<id>.json / tombstones/<id>.json），天然无冲突；
/// 各设备用 NSMetadataQuery 监听变化后合并进本地 SQLite。
///
/// 说明：iOS/iPadOS 不允许第三方 app 后台读取剪贴板，iPhone 上的历史无法被记录；
/// 同一 Apple ID 的所有 Mac 共享此目录，粘贴历史自动互通。iPhone 复制的"当前内容"
/// 经系统通用剪贴板（Handoff）落到 Mac 后，会照常被记录进历史。
@MainActor
final class iCloudSync {
    static let shared = iCloudSync()

    private(set) var isActive = false
    private var rootURL: URL?
    private var clipsDir: URL?
    private var tombstonesDir: URL?
    private var imagesDir: URL?
    private var metadataQuery: NSMetadataQuery?
    private var rescanTimer: Timer?
    private var appliedSignatures = Set<String>() // "文件名:mtime" 已处理标记

    private let fm = FileManager.default
    /// 同步事件信封：machine 用于跳过自己导出的文件
    private struct Envelope: Codable {
        var machine: String
        var clip: ClipItem?
        var deletedId: String?
        var clearAll: Bool?
    }

    // MARK: - 启停

    func start() {
        guard Settings.shared.iCloudSync else { return }
        guard let cloudDocs = cloudDocsURL else {
            NSLog("[PasteHistory] 未登录 iCloud Drive，同步停用")
            return
        }
        let root = cloudDocs.appendingPathComponent("PasteHistory", isDirectory: true)
        let clips = root.appendingPathComponent("clips", isDirectory: true)
        let tombstones = root.appendingPathComponent("tombstones", isDirectory: true)
        let images = root.appendingPathComponent("images", isDirectory: true)
        for dir in [root, clips, tombstones, images] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        rootURL = root
        clipsDir = clips
        tombstonesDir = tombstones
        imagesDir = images
        isActive = true

        // 首次启用：把本地存量全量导出一次（确定性文件名，幂等）
        if !Settings.shared.iCloudInitialExportDone {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let all = ClipStore.shared.allClipsForExport()
                for item in all {
                    self.exportClip(item)
                }
                Settings.shared.iCloudInitialExportDone = true
            }
        }

        startMetadataQuery()
        // 元数据推送不可靠时的兜底：定期 + 打开面板时全量对账
        rescanTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.importAll() }
        }
        importAll()
    }

    private var cloudDocsURL: URL? {
        let url = fm.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents", isDirectory: true)
        if url != nil { return url }
        // 未 entitlement 化时退回 CloudDocs 直路径（无 iCloud 则不存在）
        let fallback = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        return fm.fileExists(atPath: fallback.path) ? fallback : nil
    }

    // MARK: - 导出（本地操作后调用）

    func exportClip(_ item: ClipItem) {
        guard isActive, let clipsDir else { return }
        let envelope = Envelope(machine: Settings.shared.machineId, clip: item, deletedId: nil, clearAll: nil)
        writeJSON(envelope, to: clipsDir.appendingPathComponent("\(item.id.uuidString).json"))
        // 图片文件本体也带过去（内容 hash 命名，幂等）
        if item.kind == .image, let name = item.imageFile, let imagesDir {
            let src = ClipStore.shared.imagesDirectory.appendingPathComponent(name)
            let dst = imagesDir.appendingPathComponent(name)
            if fm.fileExists(atPath: src.path), !fm.fileExists(atPath: dst.path) {
                coordinatedCopy(from: src, to: dst)
            }
        }
        // 复活场景：重新导出的记录要清掉对应墓碑
        if let tombstonesDir {
            let tomb = tombstonesDir.appendingPathComponent("\(item.id.uuidString).json")
            if fm.fileExists(atPath: tomb.path) { try? fm.removeItem(at: tomb) }
        }
    }

    func exportDelete(id: UUID) {
        guard isActive, let clipsDir, let tombstonesDir else {
            NSLog("[PasteHistory] exportDelete 跳过: isActive=\(isActive)")
            return
        }
        let clipFile = clipsDir.appendingPathComponent("\(id.uuidString).json")
        do { try fm.removeItem(at: clipFile) }
        catch { NSLog("[PasteHistory] 删除记录文件失败: \(error.localizedDescription)") }
        let envelope = Envelope(machine: Settings.shared.machineId, deletedId: id.uuidString)
        writeJSON(envelope, to: tombstonesDir.appendingPathComponent("\(id.uuidString).json"))
    }

    func exportClearAll() {
        guard isActive, let clipsDir, let tombstonesDir else { return }
        // 清掉全部记录文件 + 写全局墓碑
        if let files = try? fm.contentsOfDirectory(at: clipsDir, includingPropertiesForKeys: nil) {
            for f in files { try? fm.removeItem(at: f) }
        }
        let envelope = Envelope(machine: Settings.shared.machineId, clearAll: true)
        writeJSON(envelope, to: tombstonesDir.appendingPathComponent("00000000-clear.json"))
    }

    private func writeJSON(_ envelope: Envelope, to url: URL) {
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        var coordError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { dst in
            do { try data.write(to: dst, options: .atomic) }
            catch { NSLog("[PasteHistory] 写同步文件失败: \(error.localizedDescription)") }
        }
        if let coordError {
            NSLog("[PasteHistory] 写协调失败: \(coordError.localizedDescription)")
        }
    }

    // MARK: - 导入

    func importAll() {
        guard isActive else { return }
        guard let clipsDir, let tombstonesDir else { return }

        var changed = false

        // 1) 墓碑：删除与清空（先于记录处理）
        if let files = try? fm.contentsOfDirectory(at: tombstonesDir, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for file in files where file.pathExtension == "json" {
                guard isNew(file) else { continue }
                markApplied(file)
                guard let data = readCoordinated(file),
                      let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
                      envelope.machine != Settings.shared.machineId else { continue }
                if envelope.clearAll == true {
                    ClipStore.shared.clearAllLocal()
                    changed = true
                } else if let deleted = envelope.deletedId, let id = UUID(uuidString: deleted) {
                    ClipStore.shared.removeLocal(id: id)
                    changed = true
                }
            }
        }

        // 2) 记录：upsert 合并
        if let files = try? fm.contentsOfDirectory(at: clipsDir, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for file in files where file.pathExtension == "json" {
                guard isNew(file) else { continue }
                markApplied(file)
                guard let data = readCoordinated(file),
                      let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
                      let clip = envelope.clip,
                      envelope.machine != Settings.shared.machineId else { continue }

                // 图片文件缺失则从 iCloud 目录取（未下载会失败，下次对账重试）
                if clip.kind == .image, let name = clip.imageFile, let imagesDir {
                    let local = ClipStore.shared.imagesDirectory.appendingPathComponent(name)
                    if !fm.fileExists(atPath: local.path) {
                        let remote = imagesDir.appendingPathComponent(name)
                        if fm.fileExists(atPath: remote.path) {
                            coordinatedCopy(from: remote, to: local)
                        }
                    }
                }
                ClipStore.shared.replaceLocal(clip)
                changed = true
            }
        }

        if changed {
            ClipStore.shared.reloadFromSync()
        }
    }

    /// iCloud 文件可能还没下载到本地；读之前先触发下载
    private func readCoordinated(_ url: URL) -> Data? {
        var data: Data?
        var coordError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordError) { src in
            try? FileManager.default.startDownloadingUbiquitousItem(at: src)
            data = try? Data(contentsOf: src)
        }
        return data
    }

    private func coordinatedWrite(_ data: Data, to url: URL) {
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { dst in
            try? data.write(to: dst, options: .atomic)
        }
    }

    private func coordinatedCopy(from src: URL, to dst: URL) {
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        coordinator.coordinate(readingItemAt: src, options: [],
                                writingItemAt: dst, options: .forReplacing,
                                error: &coordError) { s, d in
            try? fm.copyItem(at: s, to: d)
        }
    }

    private func isNew(_ file: URL) -> Bool {
        let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        return !appliedSignatures.contains("\(file.lastPathComponent):\(Int(mtime))")
    }

    private func markApplied(_ file: URL) {
        let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        appliedSignatures.insert("\(file.lastPathComponent):\(Int(mtime))")
    }

    // MARK: - NSMetadataQuery 监听远端变化

    private func startMetadataQuery() {
        guard let rootURL else { return }
        let query = NSMetadataQuery()
        query.searchScopes = [rootURL as NSURL]
        query.predicate = NSPredicate(format: "%K LIKE '*.json'", NSMetadataItemFSNameKey)

        NotificationCenter.default.addObserver(
            self, selector: #selector(queryDidFinishGathering),
            name: .NSMetadataQueryDidFinishGathering, object: query)
        NotificationCenter.default.addObserver(
            self, selector: #selector(queryDidUpdate),
            name: .NSMetadataQueryDidUpdate, object: query)

        query.start()
        metadataQuery = query
    }

    @objc private func queryDidFinishGathering(_ note: Notification) {
        guard let query = note.object as? NSMetadataQuery else { return }
        query.disableUpdates()
        importAll()
        query.enableUpdates()
    }

    @objc private func queryDidUpdate(_ note: Notification) {
        guard let query = note.object as? NSMetadataQuery else { return }
        query.disableUpdates()
        importAll()
        query.enableUpdates()
    }

    // MARK: - 图片恢复（维护用：从 iCloud 目录取回本地缺失的图片原图）

    func restoreImages() {
        guard let imagesDir else {
            NSLog("[PasteHistory] restoreImages 跳过：iCloud 未激活")
            return
        }
        let localDir = ClipStore.shared.imagesDirectory
        guard let files = try? fm.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil) else {
            NSLog("[PasteHistory] restoreImages：无法枚举 iCloud images 目录")
            return
        }
        var restored = 0
        for file in files {
            let dst = localDir.appendingPathComponent(file.lastPathComponent)
            if !fm.fileExists(atPath: dst.path) {
                coordinatedCopy(from: file, to: dst)
                restored += 1
            }
        }
        NSLog("[PasteHistory] restoreImages 完成：恢复 \(restored) 张")
    }

    // MARK: - 停用

    func stop() {
        metadataQuery?.stop()
        metadataQuery = nil
        rescanTimer?.invalidate()
        rescanTimer = nil
        isActive = false
    }
}

// MARK: - ClipStore 同步辅助（不触发再导出，避免回环）

extension ClipStore {
    func allClipsForExport() -> [ClipItem] {
        syncDatabase.all()
    }

    func replaceLocal(_ item: ClipItem) {
        syncDatabase.replace(item)
    }

    func removeLocal(id: UUID) {
        let item = syncDatabase.get(id: id)
        syncDatabase.delete(id: id)
        if let f = item?.imageFile { deleteImageFile(f) }
    }

    func clearAllLocal() {
        for item in syncDatabase.all() where item.imageFile != nil {
            deleteImageFile(item.imageFile)
        }
        syncDatabase.clearAll()
    }
}
