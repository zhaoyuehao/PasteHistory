import AppKit
import Foundation

/// 轮询 NSPasteboard 的 changeCount，捕获系统里任何一次复制（⌘C 等）
@MainActor
final class ClipboardMonitor {
    private let store: ClipStore
    private var lastChangeCount: Int
    private var timer: Timer?

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
            let paths = urls.map { $0.path }
            store.upsert(ClipItem(kind: .files, filePaths: paths, sourceApp: source))
            return
        }

        // 2) 图片
        if let image = NSImage(pasteboard: pb) {
            if let saved = store.saveImage(image) {
                store.upsert(ClipItem(kind: .image, imageFile: saved.name,
                                      sourceApp: source, thumbnailData: saved.thumbnail))
                return
            }
        }

        // 3) 文本
        if let text = pb.string(forType: .string) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, text.utf8.count <= 500_000 {
                store.upsert(ClipItem(kind: .text, text: text, sourceApp: source))
            }
        }
    }

    /// 手动把当前剪贴板内容存一条（菜单里"记录当前剪贴板"用）
    func captureCurrent() {
        lastChangeCount = -1
        tick()
    }
}
