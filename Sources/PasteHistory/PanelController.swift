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
    static let phToggleTree = Notification.Name("phToggleTree")
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
    private var isTreePresentation = UserDefaults.standard.object(forKey: "showDesktopTree") as? Bool ?? true
    private var placingTree = false
    private var localMonitor: Any?
    private var outsideMouseMonitor: Any?
    private var activationObserver: Any?
    private var layoutObservers: [NSObjectProtocol] = []
    var layoutEditing: Bool { panelModel.treeLayoutEditing }
    private var keyboardState = HistoryKeyboardState()
    private var previousApp: NSRunningApplication?
    /// 唤起面板前系统里聚焦的那个输入框，粘贴后要把焦点还回去
    private var previousFocusElement: AXUIElement?
    private var onPasteHandler: ((ClipItem) -> Void)?
    private let store: ClipStore
    private let observesDesktopFocus: Bool
    /// 面板与预览大窗共用的列表状态：预览内容直接跟着选中走
    let panelModel: HistoryViewModel
    private var previewStorage: PreviewPanelController?
    /// 惰性创建：构造它需要 self（owner），不能在属性初始化期拿到
    private var preview: PreviewPanelController {
        if let previewStorage { return previewStorage }
        let created = PreviewPanelController(model: panelModel, owner: self)
        previewStorage = created
        return created
    }
    init(store: ClipStore, observesDesktopFocus: Bool = true) {
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

    /// 上一次定位的结果，用来判断补位时到底有没有挪动
    private var lastPlacement: Placement?
    /// 冒烟用：`--fake-field x,y,w,h` 直接喂一个输入框矩形（AX 坐标），
    /// 绕开 AX 验证定位几何。真机上永远为 nil
    static var debugField: CGRect?
    /// 每次 show/hide 递增：作废仍在排队的"延迟切回原应用"，防止它把刚打开的面板再次打掉
    private var showGeneration = 0

    /// 淡出动画进行中：窗口还没 orderOut，但逻辑上已经算关了
    /// （否则淡出的 0.15s 里再按 ⇧⌘C 会被判成「还开着」而去走 hide）
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
        // 作废上一次 hide() 排队的 previousApp.activate()：
        // 否则快速收起后再按 ⇧⌘C，那个延迟激活会把面板顶掉 → resignKey → 面板立刻又消失
        showGeneration += 1
        isHiding = false
        endTreeLayout()
        keyboardState.edit()
        // 面板重开是一次新的会话：预览不跨会话存活
        preview.closeImmediately()

        // 打开面板 = 用户要「找」，⇧⌘V 的循环会话立刻结束
        PasteCycler.shared.end()

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

        let placement = isTreePresentation ? placeTree(panel) : place(panel, near: previousFocusElement)
        lastPlacement = placement
        installKeyMonitor()
        // 每次打开都是一次新的「找」：回到第一条、收起，一屏扫十条
        Self.post(.phPanelWillShow)
        // 没贴到输入框（常见于刚授权完的第一次）就等焦点稳定后再试一次
        if !isTreePresentation && !placement.anchored { scheduleAnchorRetry() }

        // 出现：0.22s easeOut，opacity 0→1 + scale 0.96→1。
        // 窗口淡入与内容缩放共用同一个 duration，两套时序叠加会出现「先亮后弹」。
        // 「减少动态效果」开启时跳过缩放，只保留淡入（规范 5.5：降级不是静止）
        panel.alphaValue = 0
        if !isTreePresentation && !Motion.reduceMotion, let view = panel.contentView {
            view.wantsLayer = true
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.96
            scale.toValue = 1.0
            scale.duration = 0.22
            scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
            view.layer?.add(scale, forKey: "panelAppear")
            view.layer?.transform = CATransform3DIdentity
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible, !self.layoutEditing else { return }
            self.panel?.focusSearch()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = isTreePresentation ? 0.10 : 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
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
        // 消失：0.15s 只做 opacity，不缩放。缩小消失会读出「弹回」，廉价
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in self.finishHide(generation: generation, restoreFocus: restoreFocus) }
        }
    }

    /// 淡出结束后真正收起窗口，并把焦点还回唤起面板前的应用
    private func finishHide(generation: Int, restoreFocus: Bool) {
        guard let panel, generation == showGeneration, isHiding else { return }
        panel.orderOut(nil)
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
            onPaste: pasteHandler,
            onCopyOnly: { [weak self] item in
                guard let self else { return }
                hide()
                PasteService.write(item)
                NotificationCenter.default.post(name: .pasteHistoryDidWritePasteboard, object: nil)
            },
            onClose: { [weak self] in self?.hide() },
            onPreview: { [weak self] in self?.preview.toggle() },
            onTreeModeChanged: { [weak self] enabled in self?.setTreePresentation(enabled) }
        )

        let hosting = NSHostingController(rootView: view)
        // 内容顶到窗口上缘：不要让 titlebar 的 safe area 白白吃掉顶部
        hosting.safeAreaRegions = []
        let panel = HistoryPanel(contentViewController: hosting)
        panel.title = L10n.panelTitle
        panel.applyPresentation(tree: isTreePresentation)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // 宽 340~940、高 360~1200：下限是行内解剖与扫读的存活线，上限防呆
        panel.setContentSize(NSSize(width: Panel.width, height: Panel.maxHeight))
        panel.minSize = NSSize(width: Panel.minWidth, height: Panel.minHeight)
        panel.maxSize = NSSize(width: 940, height: 1200)
        panel.delegate = self
        panel.prepareDrag = { [weak self] id in
            guard let self, !self.layoutEditing,
                  let item = self.panelModel.results.first(where: { $0.id == id }) else { return nil }
            let directory = self.store.imagesDirectory
            return { ClipDragPayload.writers(for: item, imagesDirectory: directory) }
        }
        panel.onPaperLayout = { [weak self] in self?.previewStorage?.followPaper() }
        panel.onDragUnavailable = { Toast.show("原内容不可读取，无法拖出", duration: 2) }
        panel.onDragBegan = { [weak self] in self?.preview.closeImmediately() }
        panel.onDragEnded = { [weak self] operation in
            guard let self else { return }
            let external = NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier
            if !operation.isEmpty || external { self.hide(restoreFocus: false) }
            else { self.panel?.focusSearch() }
        }
        self.panel = panel
    }

    private func setTreePresentation(_ enabled: Bool) {
        guard enabled != isTreePresentation else { return }
        isTreePresentation = enabled
        guard let panel else { return }
        preview.closeImmediately()
        // Changing window chrome can itself emit a move notification. Preserve
        // the user's tree position while switching back from the list.
        placingTree = true
        panel.applyPresentation(tree: enabled)
        lastPlacement = enabled ? placeTree(panel) : place(panel, near: previousFocusElement)
        placingTree = false
        if panel.isVisible { panel.makeKey() }
    }

    /// The tree stands in the desktop's usable area rather than inside an input-field card.
    private func placeTree(_ panel: NSPanel) -> Placement {
        let saved = UserDefaults.standard.string(forKey: "desktopTreeOrigin").map(NSPointFromString)
        let mouse = NSEvent.mouseLocation
        let screen = saved.flatMap { origin in NSScreen.screens.first { $0.visibleFrame.contains(origin) } }
            ?? NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let available = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 800)
        let stored = UserDefaults.standard.double(forKey: "desktopTreeScale")
        let scale = [0.82, 1.0, 1.14].contains(stored) ? stored : 1.0
        let height = min(920 * scale, available.height * 0.94)
        let width = min(880 * scale, available.width * 0.94, height * 1.04)
        let preferred = saved ?? NSPoint(x: available.midX-width/2, y: available.minY+12)
        let origin = NSPoint(x: min(max(preferred.x, available.minX), available.maxX-width),
                             y: min(max(preferred.y, available.minY), available.maxY-height))
        placingTree = true
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
        placingTree = false
        return Placement(origin: origin, height: height, reason: "desktop-tree", anchored: false)
    }

    func beginTreeLayout() {
        guard panel?.dragInProgress != true else { return }
        if !isVisible { show() }
        if !isTreePresentation { Self.post(.phToggleTree) }
        preview.closeImmediately()
        panel?.makeKey()
        panelModel.treeLayoutEditing = true
        panel?.layoutEditing = true
    }
    func endTreeLayout() {
        guard layoutEditing else { return }
        if isVisible { panel?.makeKey() }
        panelModel.treeLayoutEditing = false
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

    func windowDidMove(_ notification: Notification) {
        guard isTreePresentation, layoutEditing, !placingTree, let panel, panel.isVisible else { return }
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: "desktopTreeOrigin")
    }

    /// 一次定位的结果。首次没锚上时要用它决定要不要补位。
    private struct Placement {
        let origin: NSPoint
        let height: CGFloat
        let reason: String
        /// 真的贴到了输入框。false 表示退化成了居中兜底
        let anchored: Bool
    }

    /// 定位策略：贴着唤起面板的那个输入框（下方优先 → 上方），拿不到坐标才退回居中偏上。
    ///
    /// 粘贴的终点永远是输入框，视线已经在那里了：把面板放到输入框旁边，
    /// 用户不用在屏幕中央和光标之间来回搬视线。
    ///
    /// 两条硬约束：
    /// 1. **面板绝不压住输入框本体**——否则你看不到自己正要填的地方。以前只在
    ///    「上下都塞得下」时遵守，塞不下就把面板夹到屏幕边上、直接盖住输入框，
    ///    这就是「有遮挡」的来源。现在改成：塞不下就**把面板收矮**，收到恰好塞进去。
    /// 2. **位置每次重算，不记住上次**。面板的生命只有一次粘贴，
    ///    上次的落点跟这次的光标没有关系。
    private func place(_ panel: NSPanel, near element: AXUIElement?) -> Placement {
        // AX 原点在主屏左上角、y 向下；AppKit 原点在主屏左下角、y 向上
        let axisHeight = NSScreen.screens.first?.frame.height
            ?? NSScreen.main?.frame.height
            ?? 0

        // 先问「输入框在哪」，再决定用哪块屏：
        // 多屏时鼠标常在另一块屏上，按鼠标屏去夹取会把面板贴到错的地方
        var caretAX: CGRect?     // 光标那一行（AX 坐标）
        var fieldAX: CGRect?     // 输入框整框（AX 坐标）
        var role = "nil"
        if let debug = Self.debugField {
            fieldAX = debug
            role = "debug"
        } else if Settings.shared.anchorPanel, let element {
            // 焦点常常落在容器上：飞书 / 微信 / VS Code 这类把 AXFocusedUIElement
            // 报成 AXGroup / AXWebArea，真正的输入框在子节点里。向下找几层
            if let resolved = AXFocus.resolveTextInput(element) {
                role = AXFocus.role(of: resolved) ?? "?"
                caretAX = AXFocus.caretFrame(of: resolved)
                if let f = AXFocus.frame(of: resolved), f.width > 8, f.height > 8 { fieldAX = f }
            } else {
                role = AXFocus.role(of: element) ?? "?"
            }
        }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { s in
            guard let r = caretAX ?? fieldAX else { return false }
            return s.frame.contains(NSPoint(x: r.midX, y: axisHeight - r.midY))
        } ?? NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else {
            return Placement(origin: .zero, height: Panel.maxHeight, reason: "no-screen", anchored: false)
        }

        let visible = screen.visibleFrame
        let gap: CGFloat = 6      // 紧贴但不粘连，留一线
        let margin: CGFloat = 12  // 屏幕边缘留白

        // 避让对象：面板不许压在它上面。
        // 能用整框就用整框（这才是「输入框本体」），整框高得离谱（半屏的文本区）
        // 时只让开光标那一行——否则等于要求面板躲开半个屏幕，必然躲不掉。
        let toAppKit: (CGRect) -> CGRect = { r in
            CGRect(x: r.minX, y: axisHeight - r.maxY, width: r.width, height: r.height)
        }
        var avoid: CGRect?
        var alignX: CGFloat?
        if let f = fieldAX.map(toAppKit) {
            alignX = f.minX
            if f.height <= visible.height * 0.75 { avoid = f }
        }
        if avoid == nil, let c = caretAX.map(toAppKit) {
            alignX = alignX ?? c.minX
            avoid = c.insetBy(dx: -4, dy: -2)
        }

        if let a = avoid {
            let x = min(max(alignX ?? a.minX, visible.minX + margin),
                        max(visible.minX + margin, visible.maxX - Panel.width - margin))

            // 高度按可用空间收：放得下就用期望高度（用户选择或 φ 默认），放不下收到
            // 恰好塞进去，但不矮于 360。收矮比夹到屏幕边上强——夹边必然
            // 压住输入框，收矮只是少显示几行
            func fit(_ space: CGFloat) -> CGFloat {
                min(Panel.maxHeight, max(Panel.minHeight, space))
            }
            let belowSpace = a.minY - gap - (visible.minY + margin)
            let aboveSpace = (visible.maxY - margin) - (a.maxY + gap)
            let belowH = fit(belowSpace)
            let aboveH = fit(aboveSpace)

            let belowRect = CGRect(x: x, y: max(visible.minY + margin, a.minY - gap - belowH),
                                   width: Panel.width, height: belowH)
            let aboveRect = CGRect(x: x, y: min(visible.maxY - margin - aboveH, a.maxY + gap),
                                   width: Panel.width, height: aboveH)

            // 下拉优先（要的就是「在输入框那里下拉」），但只要它压住输入框就翻上方
            let belowHit = Self.overlap(belowRect, a)
            let aboveHit = Self.overlap(aboveRect, a)
            let chosen: CGRect
            let why: String
            if belowHit <= 0 {
                chosen = belowRect; why = "below-input"
            } else if aboveHit <= 0 {
                chosen = aboveRect; why = "above-input"
            } else if aboveHit < belowHit {
                chosen = aboveRect; why = "above-input-tight"
            } else {
                chosen = belowRect; why = "below-input-tight"
            }

            let height = chosen.height
            panel.setContentSize(NSSize(width: Panel.width, height: height))
            panel.setFrameOrigin(chosen.origin)
            let reason = height < Panel.maxHeight ? "\(why)/shrunk-to-\(Int(height))" : why
            self.trace("\(reason) role=\(role) panel=(\(Self.fmt(chosen))) avoid=(\(Self.fmt(a))) visible=(\(Self.fmt(visible)))")
            return Placement(origin: chosen.origin, height: height, reason: reason, anchored: true)
        }

        // 兜底：拿不到坐标（权限没给 / 自绘控件不报 AX），退回居中偏上
        panel.setContentSize(NSSize(width: Panel.width, height: Panel.maxHeight))
        let size = NSSize(width: Panel.width, height: Panel.maxHeight)
        let origin = NSPoint(x: visible.midX - size.width / 2,
                             y: max(visible.maxY - size.height - 60, visible.minY + 20))
        panel.setFrameOrigin(origin)
        let reason = Settings.shared.anchorPanel ? "fallback-center" : "anchoring-off"
        self.trace("\(reason) role=\(role) caret=\(Self.fmt(caretAX)) field=\(Self.fmt(fieldAX))")
        return Placement(origin: origin, height: Panel.maxHeight, reason: reason, anchored: false)
    }

    /// 两个矩形重叠的面积。用来判定「这个位置有没有压住输入框」
    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let w = max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX))
        let h = max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
        return w * h
    }

    // MARK: - 定位日志

    /// 真机验收只有日志能说清「没贴过去」到底是没拿到输入框还是位置算错，
    /// 所以默认就落盘（一次一行，超过 200KB 就整体重写，不会无限涨）。
    private static let traceURL: URL? = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PasteHistory")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("anchor_trace.log")
    }()

    private func trace(_ line: String) {
        guard let url = Self.traceURL else { return }
        let row = Data(String(format: "%.3f %@\n", Date().timeIntervalSince1970, line).utf8)
        let fm = FileManager.default
        let tooBig = ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0 > 200_000
        if !tooBig, let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(row)
            try? handle.close()
        } else {
            try? row.write(to: url)
        }
        if ProcessInfo.processInfo.arguments.contains("--trace-anchor") {
            NSLog("[PH] anchor: %@", line)
        }
    }

    private static func fmt(_ rect: CGRect?) -> String {
        guard let r = rect else { return "nil" }
        return String(format: "(%.0f, %.0f, %.0fx%.0f)", r.minX, r.minY, r.width, r.height)
    }

    /// 首次唤起常常拿不到输入框：辅助功能刚授权时 AX 要等一两帧才吐得出来，
    /// Electron 应用的焦点也要等它稳定。面板已经出来了就再取一次，
    /// 拿到了带 0.2s 弹簧挪过去——不是瞬移，瞬移没有阻尼感。
    private func scheduleAnchorRetry() {
        guard !isTreePresentation, Settings.shared.anchorPanel else { return }
        let generation = showGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, !self.isTreePresentation, self.showGeneration == generation, !self.isHiding,
                  let panel = self.panel, panel.isVisible else { return }
            let app = self.previousApp ?? AppTracker.targetApp()
            guard let element = app.flatMap({ AXFocus.focusedElement(pid: $0.processIdentifier) }) else { return }
            let next = self.place(panel, near: element)
            guard next.anchored else { return }
            if let last = self.lastPlacement,
               abs(last.origin.x - next.origin.x) < 1, abs(last.origin.y - next.origin.y) < 1 { return }
            self.lastPlacement = next
            self.trace("retry -> \(next.reason)")
            if Motion.reduceMotion {
                panel.setFrameOrigin(next.origin)   // 降级：直接就位，只保留淡入语义
            } else {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().setFrameOrigin(next.origin)
                }
            }
        }
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
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
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
        let key = Int(event.keyCode)
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])

        if key == 46 && mods == [.command, .shift] {
            layoutEditing ? endTreeLayout() : beginTreeLayout()
            return nil
        }
        if layoutEditing {
            if key == 53 { endTreeLayout(); return nil }
            if key == 15 && mods == [.command] {
                UserDefaults.standard.removeObject(forKey: "desktopTreeOrigin")
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
        case 49 where isTreePresentation && mods == [.shift]:
            keyboardState.edit()
            return event
        case 49 where mods == []:
            guard keyboardState.spacePreviews(query: store.query, composing: isComposingText,
                                              tree: isTreePresentation) else { return event }
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
        case 116 where isTreePresentation && mods == []: // Page Up / fn↑
            keyboardState.navigate()
            Self.post(.phPageUp); return nil
        case 121 where isTreePresentation && mods == []: // Page Down / fn↓
            keyboardState.navigate()
            Self.post(.phPageDown); return nil
        case 36, 76: // return / enter
            Self.post(.phConfirm); return nil
        case 8 where mods == [.command]: // ⌘C 仅复制
            Self.post(.phCopyOnly); return nil
        case 51 where mods == [.command]: // ⌘⌫ 删除
            Self.post(.phDelete); return nil
        case 37 where mods == [.command]: // ⌘L 列表 / 3D 许愿树
            if !event.isARepeat { Self.post(.phToggleTree) }; return nil
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
    var previewPaper: TreeInteractionPanel? {
        guard isTreePresentation, let id = panelModel.current?.id else { return nil }
        return panel?.paper(for: id)
    }
    func setExpandedPaper(_ id: UUID?) { panel?.expandedPaperID = id }
    var previewBesideTree: Bool { isTreePresentation }
    var previewAnchorVisible: Bool { (panel?.isVisible ?? false) && !isHiding }
    func makePanelKeyAgain() { panel?.makeKey(); panel?.focusSearch() }
    func dismissAllFromPreview() { hide(restoreFocus: false) }

    // MARK: - 冒烟钩子（--smoke-preview 用）

    var isPreviewVisible: Bool { preview.isVisible }
    /// 与按空格完全同一条路径
    func togglePreview() { preview.toggle() }

    // MARK: - NSWindowDelegate

    /// 用户拖边结束：记住选择。程序化的 setContentSize（避让收缩）不经过这里，
    /// 所以临时收矮不会污染用户偏好
    func windowDidEndLiveResize(_ notification: Notification) {
        guard !isTreePresentation, let panel, notification.object as? NSWindow === panel else { return }
        Settings.shared.panelWidth = panel.frame.width
        Settings.shared.panelHeight = panel.frame.height
    }

    func windowDidResignKey(_ notification: Notification) {
        // Tree mode has several key-capable input islands. Transient nil key
        // windows during their handoff are not an external dismissal. Workspace
        // activation and the passive outside-click observer own that decision.
        guard !isTreePresentation else { return }
        // 焦点的去向要等一拍才问得出（makeKey 交接有时序）：
        // 交给自己的预览窗（点选里面的文字）不算离开，真去了别的应用再收
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible, !panel.isKeyWindow, !self.isHiding else { return }
            if let key = NSApp.keyWindow,
               key === self.preview.window || (key as? TreeInteractionPanel)?.owner === panel { return }
            self.hide(restoreFocus: false)
        }
    }

    func windowWillClose(_ notification: Notification) {
        removeKeyMonitor()
    }
}
