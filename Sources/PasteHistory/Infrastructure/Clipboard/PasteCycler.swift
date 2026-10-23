import AppKit
import Foundation

/// ⇧⌘V 循环粘贴：不开面板，直接在时间轴上擦。
///
/// 第一次按下贴最近一条；继续按则 ⌘Z 撤回刚才贴进去的内容、原地换成更早一条。
/// 会话空闲 8 秒算定稿，或用户一复制新东西就立刻结束——那说明新一轮工作开始了。
/// 整个过程中焦点从未离开原输入框，也没有任何窗口出现过。
@MainActor
final class PasteCycler {
    static let shared = PasteCycler()

    /// 一次会话最多回溯多少条
    private let limit = 9
    /// 会话空闲多久算定稿。
    /// 原来 3 秒：够用来按第二次，不够用来判断「贴进去的到底是不是这条」。
    /// 想清楚再按，常常要五六秒，超时后会话一断，再按又从头开始——那是最挫败的一下。
    private static let sessionTimeout: TimeInterval = 8.0

    private var items: [ClipItem] = []
    private var index = 0
    private var target: NSRunningApplication?
    private var focusElement: AXUIElement?
    /// 首次按下需要 activate 原应用并等焦点稳定；后续不用重复切
    private var activated = false
    private var idleTimer: DispatchWorkItem?
    /// 上一次我们自己往剪贴板回写的时刻。
    /// 回写同样会 bump changeCount，若轮询抢在 syncChangeCount 之前跑，
    /// 监视器会把「我们自己贴的这条」当成用户的新复制——于是第一次按下就被自己掐断。
    private var lastSelfWriteAt: Date = .distantPast
    /// 抑制窗口：略大于一轮轮询间隔（0.4s）
    private static let selfWriteGrace: TimeInterval = 0.6

    var isActive: Bool { !items.isEmpty }

    private init() {
        // 用户一复制新东西，这次回溯就该收工了：他要的是刚复制的那条，
        // 而不是继续往下翻。计时不该是唯一能结束会话的东西。
        NotificationCenter.default.addObserver(forName: .pasteHistoryDidCapture,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // 刚刚是我们自己在写剪贴板，不是用户复制了新东西
                guard Date().timeIntervalSince(self.lastSelfWriteAt) > Self.selfWriteGrace else { return }
                self.end()
            }
        }
    }

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
            UserFeedback.show(L10n.noClipboardHistory)
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

        lastSelfWriteAt = Date()
        PasteService.write(item)
        NotificationCenter.default.post(name: .pasteHistoryDidWritePasteboard, object: nil)

        guard Settings.shared.autoPaste else {
            UserFeedback.show(L10n.pasteToClipboard)
            end()
            return
        }
        guard PasteService.isTrusted() else {
            UserFeedback.show(L10n.pasteToClipboard, duration: 3)
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
