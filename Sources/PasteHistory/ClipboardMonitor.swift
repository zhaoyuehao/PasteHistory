import AppKit
import Foundation

/// 轮询 NSPasteboard 的 changeCount，捕获系统里任何一次复制（⌘C 等）
@MainActor
final class ClipboardMonitor {
    private let store: ClipStore
    private var lastChangeCount: Int
    private var timer: Timer?

    /// 刚捕获的一条记录，用于合并「同一次复制被应用拆成多次写剪贴板」的图文
    /// （比如先写文字、隔几百毫秒再补图片，轮询会抓到两条）。窗口内互补类型直接合并。
    private struct PendingMerge {
        let id: UUID
        let kind: ClipKind
        let source: String?
        let at: Date
    }
    private var lastCapture: PendingMerge?
    /// 合并窗口：应用拆写通常在 1 秒内完成，而人手连续两次复制很少这么快
    private static let mergeWindow: TimeInterval = 1.2

    init(store: ClipStore = ClipStore.shared) {
        self.store = store
        self.lastChangeCount = MainActor.assumeIsolated {
            NSPasteboard.general.changeCount
        }
    }

    func start() {
        stop()
        let t = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.tick() }
        }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 我们自己往剪贴板写内容后调用，避免把回写当新条目记录
    func syncChangeCount() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func tick() {
        let pb = NSPasteboard.general
        let current = pb.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        if Settings.shared.paused { return }
        if Settings.shared.isIgnored(bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier) {
            return
        }

        // nspasteboard.org 行业约定：按标记类型区分剪贴板内容性质
        let types = Set(pb.types?.map { $0.rawValue } ?? [])

        // 保密内容（密码管理器标记）不记录
        let concealedMarkers = [
            "org.nspasteboard.ConcealedType",
            "com.agilebits.onepassword",
        ]
        if concealedMarkers.contains(where: types.contains) { return }

        // 瞬态内容（TextExpander/Butler 等临时中转）不记录
        let transientMarkers = [
            "org.nspasteboard.TransientType",
            "de.petermaurer.TransientPasteboardType",
            "com.typeit4me.clipping",
        ]
        if transientMarkers.contains(where: types.contains) { return }

        // Apple 私有类型：标记内容来自另一台设备的接力（通用剪贴板）
        let isRemote = types.contains("com.apple.is-remote-clipboard")
        let source = isRemote
            ? "接力 · iPhone/iPad"
            : NSWorkspace.shared.frontmostApplication?.localizedName

        // 1) 文件（Finder 复制的文件/文件夹）
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty,
           urls.allSatisfy({ $0.isFileURL }) {
            lastCapture = nil
            let paths = urls.map { $0.path }
            var item = ClipItem(kind: .files, filePaths: paths, sourceApp: source)
            // 图片文件（如微信复制的 jpg）：生成列表缩略图，OCR 由 upsert 触发
            if let imgPath = item.firstImageFilePath,
               let cg = Self.loadCGImage(atPath: imgPath) {
                item.thumbnailData = ClipStore.makeThumbnail(cg: cg)
            }
            store.upsert(item)
            noteCaptured()
            return
        }

        // 2) 图片（同一次复制附带的文字一起收进同一条，不再拆成两条）
        if let image = NSImage(pasteboard: pb) {
            if let saved = store.saveImage(image) {
                let caption = pb.string(forType: .string)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let text = (caption != nil && !caption!.isEmpty && caption!.utf8.count <= 500_000) ? caption : nil

                // 应用拆写：上一条是同来源的纯文本且刚入库 → 图片合并进上一条
                if let pending = lastCapture, pending.kind == .text,
                   pending.source == source,
                   Date().timeIntervalSince(pending.at) < Self.mergeWindow,
                   store.attachImage(id: pending.id, saved: saved, caption: text) {
                    lastCapture = nil
                    noteCaptured()
                    return
                }

                let item = ClipItem(kind: .image, text: text, imageFile: saved.name,
                                    sourceApp: source, thumbnailData: saved.thumbnail)
                if store.upsert(item) {
                    lastCapture = PendingMerge(id: item.id, kind: .image, source: source, at: Date())
                    noteCaptured()
                }
                return
            }
        }

        // 3) 文本
        if let text = pb.string(forType: .string) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, text.utf8.count <= 500_000 {
                // 应用拆写：上一条是同来源的图片且还没有文字 → 文字合并进上一条
                if let pending = lastCapture, pending.kind == .image,
                   pending.source == source,
                   Date().timeIntervalSince(pending.at) < Self.mergeWindow,
                   store.attachText(id: pending.id, text: trimmed) {
                    lastCapture = nil
                    noteCaptured()
                    return
                }

                let item = ClipItem(kind: .text, text: trimmed, sourceApp: source)
                if store.upsert(item) {
                    lastCapture = PendingMerge(id: item.id, kind: .text, source: source, at: Date())
                    noteCaptured()
                }
            }
        }
    }

    /// 捕获成功：菜单栏图标「点头」一下（不弹通知、不出声）
    private func noteCaptured() {
        NotificationCenter.default.post(name: .pasteHistoryDidCapture, object: nil)
    }

    /// 用 CGImageSource 直接从磁盘解码图片（比 NSImage 更适合非 UI 场景）
    nonisolated static func loadCGImage(atPath path: String) -> CGImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

extension Notification.Name {
    static let pasteHistoryDidCapture = Notification.Name("pasteHistoryDidCapture")
}
