import AppKit
import Foundation

/// ⇧⌘V 循环粘贴：不开面板，直接在时间轴上擦。
///
/// 第一次按下贴最近一条；继续按则 ⌘Z 撤回刚才贴进去的内容、原地换成更早一条。
/// 会话在 3 秒无操作后自动结束（此时再按会重新开始）。
/// 整个过程中焦点从未离开原输入框，也没有任何窗口出现过。
@MainActor
final class PasteCycler {
    static let shared = PasteCycler()

    /// 一次会话最多回溯多少条
    private let limit = 9
    /// 会话空闲多久算定稿
    private static let sessionTimeout: TimeInterval = 3.0

    private var items: [ClipItem] = []
    private var index = 0
    private var target: NSRunningApplication?
    private var focusElement: AXUIElement?
    /// 首次按下需要 activate 原应用并等焦点稳定；后续不用重复切
    private var activated = false
    private var idleTimer: DispatchWorkItem?

    var isActive: Bool { !items.isEmpty }

    /// 每次按下 ⇧⌘V 调用
    func advance() {
        guard !items.isEmpty else {
            begin()
            scheduleIdle()
            return
        }
        index = (index + 1) % items.count
        apply(undoFirst: true)
        scheduleIdle()
    }

    /// 打开面板视为「我要找东西」，循环会话立刻结束
    func end() {
        items = []
        index = 0
        target = nil
        focusElement = nil
        activated = false
        idleTimer?.cancel()
        idleTimer = nil
    }

    // MARK: - 内部

    private func begin() {
        items = ClipStore.shared.recent(limit)
        guard !items.isEmpty else {
            Toast.show(L10n.noClipboardHistory)
            return
        }
        index = 0
        activated = false
        target = AppTracker.targetApp()
        focusElement = target.flatMap { AXFocus.focusedElement(pid: $0.processIdentifier) }
        apply(undoFirst: false)
    }

    /// undoFirst：先撤回上一次贴入，再贴当前这条
    private func apply(undoFirst: Bool) {
        guard index < items.count else { return }
        let item = items[index]

        PasteService.write(item)
        NotificationCenter.default.post(name: .pasteHistoryDidWritePasteboard, object: nil)

        guard Settings.shared.autoPaste else {
            Toast.show(L10n.pasteToClipboard)
            end()
            return
        }
        guard PasteService.isTrusted() else {
            Toast.show(L10n.pasteToClipboard, duration: 3)
            end()
            return
        }

        if !activated {
            target?.activate()
            activated = true
        }

        let settle = undoFirst ? 0.12 : 0.25
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) { [weak self] in
            Task { @MainActor in self?.send(undoFirst: undoFirst) }
        }
    }

    private func send(undoFirst: Bool) {
        guard isActive else { return }
        if undoFirst { PasteService.sendCommandZ() }
        if let focusElement { AXFocus.focus(focusElement) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            PasteService.sendCommandV()
        }
    }

    private func scheduleIdle() {
        idleTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.end() }
        }
        idleTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.sessionTimeout, execute: work)
    }
}
