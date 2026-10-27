import AppKit
import QuartzCore
import SwiftUI

extension Notification.Name {
    static let phPageUp = Notification.Name("phPageUp")
    static let phPageDown = Notification.Name("phPageDown")
    static let phTreeSize = Notification.Name("phTreeSize")
    static let phFinishTreeLayout = Notification.Name("phFinishTreeLayout")
    static let phResetTree = Notification.Name("phResetTree")
    static let phMoveUp = Notification.Name("phMoveUp")
    static let phMoveDown = Notification.Name("phMoveDown")
    static let phConfirm = Notification.Name("phConfirm")
    static let phCopyOnly = Notification.Name("phCopyOnly")
    static let phDelete = Notification.Name("phDelete")
    static let phPin = Notification.Name("phPin")
    static let phClose = Notification.Name("phClose")
    static let phQuickPaste = Notification.Name("phQuickPaste")
    /// 面板即将显示：视图收到后回到第一条
    static let phPanelWillShow = Notification.Name("phPanelWillShow")
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let shared = PanelController(store: .shared)

    private var panel: HistoryPanel?
    private let treeEntrance = TreeEntrance()
    private var localMonitor: Any?
    private var outsideMouseMonitor: Any?
    private var activationObserver: Any?
    private var layoutObservers: [NSObjectProtocol] = []
    private let presentation = HistoryPresentationState()
    private let pairing: PairModel
    var layoutEditing: Bool { presentation.treeLayoutEditing }
    private var keyboardState = HistoryKeyboardState()
    private var previousApp: NSRunningApplication?
    /// 唤起面板前系统里聚焦的那个输入框，粘贴后要把焦点还回去
    private var previousFocusElement: AXUIElement?
    private var onPasteHandler: ((ClipItem) -> Void)?
    private let store: ClipStore
    private let observesDesktopFocus: Bool
    /// 树与预览共用的选择状态：预览内容直接跟着选中走
    let panelModel: HistoryViewModel
    private var previewStorage: PreviewPanelController?
    /// 惰性创建：构造它需要 self（owner），不能在属性初始化期拿到
    private var preview: PreviewPanelController {
        if let previewStorage { return previewStorage }
        let created = PreviewPanelController(model: panelModel, owner: self, presentation: presentation, pairing: pairing)
        previewStorage = created
        return created
    }
    init(store: ClipStore, observesDesktopFocus: Bool = true, pairing: PairModel? = nil) {
        self.pairing = pairing ?? PairModel()
        self.store = store
        self.observesDesktopFocus = observesDesktopFocus
        self.panelModel = HistoryViewModel(store: store)
        super.init()
        layoutObservers = [
            NotificationCenter.default.addObserver(forName: .phTreeSize, object: nil, queue: .main) { [weak self] note in
                guard let size = note.object as? Double else { return }
                self?.setTreeSize(size)
            },
            NotificationCenter.default.addObserver(forName: .phFinishTreeLayout, object: nil, queue: .main) { [weak self] _ in
                self?.endTreeLayout()
            }
        ]
    }

    /// 每次 show/hide 递增：作废仍在排队的"延迟切回原应用"，防止它把刚打开的面板再次打掉
    private var showGeneration = 0

    /// 淡出动画进行中：窗口还没 orderOut，但逻辑上已经算关了
    /// （否则淡出的 0.15s 里再按 ⇧⌘V 会被判成「还开着」而去走 hide）
    private var isHiding = false

    var isVisible: Bool { (panel?.isVisible ?? false) && !isHiding }

    /// 冒烟用：不经过 UI，直接走「面板里选中并回车」的同一条粘贴路径
    func pasteItem(_ item: ClipItem) {
        onPasteHandler?(item)
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        guard panel?.dragInProgress != true else { return }
        if panel == nil { buildPanel() }
        guard let panel else { return }
        if panel.isVisible && !isHiding {
            panel.focusSearch()
            return
        }
        let continuingOrigin = panel.isVisible ? panel.frame.origin : nil
        // 作废上一次 hide() 排队的 previousApp.activate()：
        // 否则快速收起后再按 ⇧⌘V，那个延迟激活会把面板顶掉 → resignKey → 面板立刻又消失
        showGeneration += 1
        isHiding = false
        endTreeLayout()
        keyboardState.edit()
        // 面板重开是一次新的会话：预览不跨会话存活
        preview.closeImmediately()

        // 打开面板时顺手对账一次 iCloud 远端变化
        iCloudSync.shared.importAll()

        // 记住唤起面板前的前台应用和它当前聚焦的输入框，粘贴时要原样还回去
        let target = AppTracker.targetApp()
        previousApp = target
        previousFocusElement = target.flatMap { AXFocus.focusedElement(pid: $0.processIdentifier) }
        NSLog("[PH] show: target=%@ pid=%d focusElement=%@",
              target?.localizedName ?? "nil",
              target?.processIdentifier ?? -1,
              previousFocusElement == nil ? "nil" : "有")

        let origin = placeTree(panel)
        installKeyMonitor()
        // 每次打开都是一次新的「找」：回到第一条
        Self.post(.phPanelWillShow)
        if continuingOrigin == nil { panel.treeOpacity = 0 }
        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible, !self.layoutEditing else { return }
            self.panel?.focusSearch()
        }
        // Begin after ordering and activation so the full entrance remains visible.
        treeEntrance.present(panel, target: origin, from: continuingOrigin)
    }

    func hide(restoreFocus: Bool = true) {
        guard let panel, panel.isVisible, !isHiding, !panel.dragInProgress else { return }
        showGeneration += 1
        let generation = showGeneration
        isHiding = true
        removeKeyMonitor()
        endTreeLayout()
        // No orphan flight or input window when the entire tree disappears.
        preview.closeImmediately()
        // Child input windows disappear immediately: an invisible fading paper
        // must never keep intercepting the desktop.
        panel.suspendIslands()
        treeEntrance.dismiss(panel) { [weak self] in
            self?.finishHide(generation: generation, restoreFocus: restoreFocus)
        }
    }

    /// 淡出结束后真正收起窗口，并把焦点还回唤起面板前的应用
    private func finishHide(generation: Int, restoreFocus: Bool) {
        guard let panel, generation == showGeneration, isHiding else { return }
        panel.orderOut(nil)
        panel.treeOpacity = 1
        panel.alphaValue = 1
        isHiding = false
        guard restoreFocus, let app = previousApp else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            // 期间又 show() 过（面板可见）就不抢焦点
            guard let self, self.showGeneration == generation,
                  !(self.panel?.isVisible ?? false) else { return }
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            guard front == nil || front == ProcessInfo.processInfo.processIdentifier || front == app.processIdentifier else { return }
            app.activate()
        }
    }

    // MARK: - 构建

    private func buildPanel() {
        let pasteHandler: (ClipItem) -> Void = { [weak self] item in
            guard let self else { return }
            let target = previousApp
            let element = previousFocusElement
            hide()
            PasteService.paste(item, to: target, focusElement: element)
        }
        onPasteHandler = pasteHandler

        let view = HistoryView(
            store: store,
            model: panelModel,
            presentation: presentation,
            onPaste: pasteHandler,
            onCopyOnly: { [weak self] item in
                guard let self else { return }
                hide()
                PasteService.write(item)
                NotificationCenter.default.post(name: .pasteHistoryDidWritePasteboard, object: nil)
            },
            onClose: { [weak self] in self?.hide() },
            onPreview: { [weak self] in
                guard let self else { return }
                keyboardState.navigate()
                preview.presentSelection()
            }
        )

        let hosting = NSHostingController(rootView: view)
        // 内容顶到窗口上缘：不要让 titlebar 的 safe area 白白吃掉顶部
        hosting.safeAreaRegions = []
        let panel = HistoryPanel(contentViewController: hosting)
        panel.title = L10n.panelTitle
        panel.configureTree()
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.prepareDrag = { [weak self] id in
            guard let self, !self.layoutEditing,
                  let item = self.panelModel.results.first(where: { $0.id == id }) else { return nil }
            let directory = self.store.imagesDirectory
            return { ClipDragPayload.writers(for: item, imagesDirectory: directory) }
        }
        panel.mergeCards = { [weak self] sourceID, targetID in
            guard let self else { return false }
            let merged = self.store.merge(primaryID: targetID, secondaryID: sourceID)
            if merged {
                Toast.show(L10n.mergeSucceeded, duration: 2)
                self.panelModel.rebuildResults()
                if let index = self.panelModel.results.firstIndex(where: { $0.id == targetID }) {
                    self.panelModel.select(index)
                }
            } else {
                Toast.show(L10n.mergeUnsupported, duration: 2.5)
            }
            return merged
        }
        panel.onPaperLayout = { [weak self] in self?.previewStorage?.followPaper() }
        panel.onDragUnavailable = { Toast.show("原内容不可读取，无法拖出", duration: 2) }
        panel.onDragBegan = { [weak self] in self?.preview.closeImmediately() }
        panel.onDragEnded = { [weak self] operation in
            guard let self else { return }
            if operation == .link {
                self.panel?.focusSearch()
                return
            }
            let external = NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier
            if !operation.isEmpty || external { self.hide(restoreFocus: false) }
            else { self.panel?.focusSearch() }
        }
        self.panel = panel
    }

    /// Each presentation centers the whole tree on the screen under the pointer.
    /// Input focus is captured only for pasting back, never for window placement.
    private func placeTree(_ panel: NSPanel) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let available = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 800)
        let stored = UserDefaults.standard.double(forKey: "desktopTreeScale")
        let scale = [0.82, 1.0, 1.14].contains(stored) ? stored : 1.0
        let frame = Self.centeredTreeFrame(in: available, scale: scale)
        panel.setFrame(frame, display: true)
        return frame.origin
    }

    static func centeredTreeFrame(in available: NSRect, scale: Double) -> NSRect {
        let height = min(920 * scale, available.height * 0.94)
        let width = min(880 * scale, available.width * 0.94, height * 1.04)
        return NSRect(x: available.midX - width / 2, y: available.midY - height / 2,
                      width: width, height: height)
    }

    func beginTreeLayout() {
        guard panel?.dragInProgress != true else { return }
        let opening = !isVisible
        if opening { show() }
        preview.closeImmediately()
        panel?.makeKey()
        treeEntrance.cancel()
        // Layout opened from the menu must settle at the centered destination,
        // not at the first (lowered) frame of the entrance animation.
        if opening, let panel { _ = placeTree(panel) }
        panel?.treeOpacity = 1
        presentation.treeLayoutEditing = true
        panel?.layoutEditing = true
    }
    func endTreeLayout() {
        guard layoutEditing else { return }
        if isVisible { panel?.makeKey() }
        presentation.treeLayoutEditing = false
        panel?.layoutEditing = false
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible, !self.layoutEditing else { return }
            self.panel?.focusSearch()
        }
    }
    private func setTreeSize(_ size: Double) {
        guard layoutEditing, [0.82, 1.0, 1.14].contains(size), let panel else { return }
        UserDefaults.standard.set(size, forKey: "desktopTreeScale")
        _ = placeTree(panel)
    }

    // MARK: - 键盘（面板内快捷键）

    private func installKeyMonitor() {
        removeKeyMonitor()
        // Isolated UI regression runs may omit real desktop observers so unrelated
        // user activity doesn't dismiss synthetic windows during assertions.
        if observesDesktopFocus {
            outsideMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                self?.hide(restoreFocus: false)
            }
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                self?.hide(restoreFocus: false)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    private func removeKeyMonitor() {
        if let outsideMouseMonitor { NSEvent.removeMonitor(outsideMouseMonitor); self.outsideMouseMonitor = nil }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver); self.activationObserver = nil }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private static func post(_ name: Notification.Name, object: Any? = nil) {
        NotificationCenter.default.post(name: name, object: object)
    }

    /// Shared dispatch path, also exercised by isolated keyboard regression tests.
    func handle(_ event: NSEvent) -> NSEvent? {
        if panel?.dragInProgress == true { return event } // Escape belongs to the native drag session.
        if event.type == .leftMouseDown {
            // Clicking back into search returns Delete to the text editor.
            if let content = event.window?.contentView {
                var hit = content.hitTest(content.convert(event.locationInWindow, from: nil))
                while let view = hit {
                    if (view as? NSTextView)?.isEditable == true || (view as? NSTextField)?.isEditable == true {
                        keyboardState.edit()
                        break
                    }
                    hit = view.superview
                }
            }
            return event
        }
        let key = Int(event.keyCode)
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])

        if key == 46 && mods == [.command, .shift] {
            layoutEditing ? endTreeLayout() : beginTreeLayout()
            return nil
        }
        if layoutEditing {
            if key == 53 { endTreeLayout(); return nil }
            if key == 15 && mods == [.command] {
                UserDefaults.standard.removeObject(forKey: "desktopTreeScale")
                if let panel { _ = placeTree(panel) }
                Self.post(.phResetTree)
                return nil
            }
            return event
        }
        // Candidate navigation and commit belong to the input method while composing.
        if isComposingText && [125, 126, 36, 76, 116, 121].contains(key) { return event }
        switch key {
        case 53: // esc：两层退出——预览开着先关预览，再按才收面板
            // 输入法组词中：Esc 是「取消组词」，得还给输入法（顺带修掉老问题——
            // 以前打着字按 Esc 面板直接没了，组词却还挂着）
            if isComposingText { return event }
            if preview.isVisible {
                if !event.isARepeat { preview.close() }
            } else {
                Self.post(.phClose)
            }
            return nil
        case 49 where mods == [.shift]:
            keyboardState.edit()
            return event
        case 49 where mods == []:
            guard keyboardState.spacePreviews(composing: isComposingText) else { return event }
            if !event.isARepeat { preview.toggle() }
            return nil
        case 16 where mods == [.command]: // ⌘Y：预览的兜底别名，任何时候可用
            if event.isARepeat { return nil }
            preview.toggle()
            return nil
        case 126: // ↑
            keyboardState.navigate()
            Self.post(.phMoveUp); return nil
        case 125: // ↓
            keyboardState.navigate()
            Self.post(.phMoveDown); return nil
        case 116 where mods == []: // Page Up / fn↑
            keyboardState.navigate()
            Self.post(.phPageUp); return nil
        case 121 where mods == []: // Page Down / fn↓
            keyboardState.navigate()
            Self.post(.phPageDown); return nil
        case 36, 76: // return / enter
            Self.post(.phConfirm); return nil
        case 8 where mods == [.command]: // ⌘C 仅复制
            Self.post(.phCopyOnly); return nil
        case 51 where mods == [], 117 where mods == []: // Delete / forward Delete
            guard keyboardState.deleteRemovesCard(query: store.query, composing: isComposingText) else {
                return event
            }
            if !event.isARepeat { Self.post(.phDelete) }
            return nil
        case 35 where mods == [.command]: // ⌘P 置顶
            Self.post(.phPin); return nil
        case 13 where mods == [.command]: // ⌘W 关闭
            Self.post(.phClose); return nil
        default:
            break
        }

        // ⌘1~⌘9 快速粘贴
        if mods == [.command] {
            let digitMap: [Int: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
            if let n = digitMap[key] {
                Self.post(.phQuickPaste, object: n - 1)
                return nil
            }
        }
        if !mods.contains(.command) && !mods.contains(.control),
           key == 51 || !(event.characters ?? "").isEmpty {
            keyboardState.edit()
        }
        return event
    }

    /// 输入法正在组词吗（marked text 非空）：中文输入法打到一半时，
    /// 空格和 Esc 都有输入法自己的含义，不能当面板快捷键劫走
    private var isComposingText: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder,
              let editor = responder as? NSTextView else { return false }
        return editor.markedRange().length > 0
    }

    // MARK: - 预览窗联动（PreviewPanelController 回调）

    var previewAnchorFrame: NSRect? { panel?.frame }
    var previewSelectionID: UUID? {
        presentation.phoneSyncSelected ? IvoryTreeEntry.phoneSyncID : panelModel.current?.id
    }
    var previewPaper: TreeInteractionPanel? {
        guard let id = previewSelectionID else { return nil }
        return panel?.paper(for: id)
    }
    func previewPaper(for id: UUID?) -> TreeInteractionPanel? {
        id.flatMap { panel?.paper(for: $0) }
    }
    func setExpandedPaper(_ id: UUID?) { panel?.expandedPaperID = id }
    var previewAnchorVisible: Bool { (panel?.isVisible ?? false) && !isHiding }
    func makePanelKeyAgain() { panel?.makeKey(); panel?.focusSearch() }

    // MARK: - 冒烟钩子（--smoke-preview 用）

    var isPreviewVisible: Bool { preview.isVisible }
    var isPreviewAnimating: Bool { previewStorage?.isAnimating ?? false }
    var previewWindow: NSPanel? { previewStorage?.window }
    /// 与按空格完全同一条路径
    func togglePreview() { preview.toggle() }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        removeKeyMonitor()
    }
}
