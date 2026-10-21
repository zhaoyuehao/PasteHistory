import AppKit
import QuartzCore
import SwiftUI

extension Notification.Name {
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
    static let shared = PanelController()

    private var panel: NSPanel?
    private var localMonitor: Any?
    private var previousApp: NSRunningApplication?
    /// 唤起面板前系统里聚焦的那个输入框，粘贴后要把焦点还回去
    private var previousFocusElement: AXUIElement?
    private var onPasteHandler: ((ClipItem) -> Void)?
    private let store = ClipStore.shared
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
        if panel == nil { buildPanel() }
        guard let panel else { return }
        // 作废上一次 hide() 排队的 previousApp.activate()：
        // 否则快速收起后再按 ⇧⌘C，那个延迟激活会把面板顶掉 → resignKey → 面板立刻又消失
        showGeneration += 1
        isHiding = false

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

        place(panel, near: previousFocusElement)
        installKeyMonitor()
        // 每次打开都是一次新的「找」：回到第一条、收起，一屏扫十条
        Self.post(.phPanelWillShow)

        // 出现：0.22s easeOut，opacity 0→1 + scale 0.96→1。
        // 窗口淡入与内容缩放共用同一个 duration，两套时序叠加会出现「先亮后弹」
        panel.alphaValue = 0
        if let view = panel.contentView {
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
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible, !isHiding else { return }
        showGeneration += 1
        let generation = showGeneration
        isHiding = true
        removeKeyMonitor()
        // 消失：0.15s 只做 opacity，不缩放。缩小消失会读出「弹回」，廉价
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in self.finishHide(generation: generation) }
        }
    }

    /// 淡出结束后真正收起窗口，并把焦点还回唤起面板前的应用
    private func finishHide(generation: Int) {
        guard let panel else { return }
        panel.orderOut(nil)
        panel.alphaValue = 1
        isHiding = false
        guard let app = previousApp else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            // 期间又 show() 过（面板可见）就不抢焦点
            guard let self, self.showGeneration == generation,
                  !(self.panel?.isVisible ?? false) else { return }
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
            onPaste: pasteHandler,
            onCopyOnly: { [weak self] item in
                guard let self else { return }
                hide()
                PasteService.write(item)
                NotificationCenter.default.post(name: .pasteHistoryDidWritePasteboard, object: nil)
            },
            onClose: { [weak self] in self?.hide() }
        )

        let hosting = NSHostingController(rootView: view)
        // 内容顶到窗口上缘：不要让 titlebar 的 safe area 白白吃掉顶部
        hosting.safeAreaRegions = []
        let panel = NSPanel(contentViewController: hosting)
        // 520×540 固定，不可 resize：工具不是家具，不该让用户承担调尺寸的责任。
        // 窗口尺寸不参与展开动画（高度固定），否则窗口动画与内容动画会打架
        panel.styleMask = [.titled, .closable, .fullSizeContentView, .nonactivatingPanel]
        panel.title = L10n.panelTitle
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        // 藏掉红绿灯：这是一张卡片，不是一扇窗户
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.setContentSize(NSSize(width: 520, height: 540))
        panel.minSize = NSSize(width: 520, height: 540)
        panel.maxSize = NSSize(width: 520, height: 540)
        panel.delegate = self
        self.panel = panel
    }

    /// 定位策略：优先贴着唤起面板的那个输入框（下方 → 上方），拿不到坐标就退回居中偏上。
    ///
    /// 粘贴的终点永远是输入框，视线已经在那里了：把面板放到输入框旁边，
    /// 用户不用在屏幕中央和光标之间来回搬视线。硬约束是**面板绝不压住输入框本体**——
    /// 否则你就看不到自己正要填的地方。
    private func place(_ panel: NSPanel, near element: AXUIElement?) {
        // AX 原点在主屏左上角、y 向下；AppKit 原点在主屏左下角、y 向上
        let axisHeight = NSScreen.screens.first?.frame.height
            ?? NSScreen.main?.frame.height
            ?? 0

        // 先问「输入框在哪」，再决定用哪块屏：
        // 多屏时鼠标常在另一块屏上，按鼠标屏去夹取会把面板贴到错的地方
        var anchor: (rect: CGRect, screen: NSScreen)?
        let tracing = Self.traceURL != nil
        if Settings.shared.anchorPanel, let element {
            // 优先贴光标：文本区可能半屏高，整框贴上去必挡正文；光标才是你在看的位置。
            // 能取到光标的一定是文本类元素（按钮、窗口没有 AXSelectedTextRange），
            // 所以这一路不看角色——自绘控件的角色名字常常不在白名单里。
            let caret = AXFocus.caretFrame(of: element)
            let whole = AXFocus.frame(of: element)
            let role = AXFocus.role(of: element)
            if tracing {
                trace(String(format: "probe app=%@ role=%@ trusted=%@ caret=%@ frame=%@",
                             AppTracker.targetApp()?.localizedName ?? "nil",
                             role ?? "nil",
                             PasteService.isTrusted() ? "yes" : "no",
                             Self.fmt(caret), Self.fmt(whole)))
            }
            if let caret {
                let center = NSPoint(x: caret.midX, y: axisHeight - caret.midY)
                if let s = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
                    anchor = (caret, s)
                } else if tracing {
                    trace("caret center not on any screen -> skip")
                }
            }
            // 拿不到光标（部分自绘控件）再退回整框，但要认角色 + 尺寸像个输入框
            if anchor == nil,
               AXFocus.isTextInput(element),      // 窗口 / 容器不算输入框
               let field = whole,
               field.width > 8, field.height > 8 {
                let center = NSPoint(x: field.midX, y: axisHeight - field.midY)
                if let s = NSScreen.screens.first(where: { $0.frame.contains(center) }),
                   field.height <= s.visibleFrame.height / 2 {
                    anchor = (field, s)
                } else if tracing {
                    trace("frame rejected (off-screen or taller than half screen)")
                }
            }
        } else if tracing {
            trace("anchorPanel=\(Settings.shared.anchorPanel) element=\(element == nil ? "nil" : "有")")
        }

        let mouse = NSEvent.mouseLocation
        let screen = anchor?.screen
            ?? NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let visible = screen.visibleFrame
        let size = panel.frame.size
        let gap: CGFloat = 6      // 紧贴但不粘连，留一线
        let margin: CGFloat = 12  // 屏幕边缘留白

        // --trace-anchor 时把每次定位都写进文件，这样用真快捷键（不是 Terminal 启动）
        // 触发的场景也能复盘——从 Terminal 启动会把前台抢走，探针永远探不到真实输入框
        let apply: (NSPoint, String, CGRect?) -> Void = { origin, why, field in
            panel.setFrameOrigin(origin)
            guard tracing else { return }
            self.trace(String(format: "%@ panel=(%.0f, %.0f) visible=(%.0f, %.0f, %.0fx%.0f) anchor=%@",
                              why,
                              origin.x, origin.y,
                              visible.minX, visible.minY, visible.width, visible.height,
                              Self.fmt(field)))
        }

        if let (field, _) = anchor {
            let top = axisHeight - field.minY      // 输入框上缘（AppKit y）
            let bottom = axisHeight - field.maxY   // 输入框下缘（AppKit y）

            let x = min(max(field.minX, visible.minX + margin),
                        max(visible.minX + margin, visible.maxX - size.width - margin))

            // 先试下方：大多数输入框上方是内容区，往下让开更不挡视线
            if bottom - gap - size.height >= visible.minY + margin {
                apply(NSPoint(x: x, y: bottom - gap - size.height), "below-input", field)
                return
            }
            // 下方不够（输入框靠近屏幕底）就翻到上方
            if top + gap + size.height <= visible.maxY - margin {
                apply(NSPoint(x: x, y: top + gap), "above-input", field)
                return
            }
            // 上下都塞不下（可视区比面板还矮）：贴着空间大的一边，够不着就居中
            let below = bottom - visible.minY
            let above = visible.maxY - top
            if below >= above {
                apply(NSPoint(x: x, y: max(visible.minY + margin, bottom - gap - size.height)),
                      "below-input-clamped", field)
            } else {
                apply(NSPoint(x: x, y: min(visible.maxY - size.height - margin, top + gap)),
                      "above-input-clamped", field)
            }
            return
        }

        // 兜底：自绘控件 / Electron 应用不报准确坐标，退回原来的居中偏上
        let x = visible.midX - size.width / 2
        let y = visible.maxY - size.height - 60
        apply(NSPoint(x: x, y: max(y, visible.minY + 20)),
              Settings.shared.anchorPanel ? "fallback-center" : "anchoring-off",
              nil)
    }

    // MARK: - 定位诊断

    /// --trace-anchor 时才有值。写文件而不是 NSLog：真快捷键触发的场景看不到 stdout
    private static let traceURL: URL? = {
        guard ProcessInfo.processInfo.arguments.contains("--trace-anchor") else { return nil }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PasteHistory/anchor_trace.log")
    }()

    private func trace(_ line: String) {
        guard let url = Self.traceURL else { return }
        let text = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    private static func fmt(_ rect: CGRect?) -> String {
        guard let r = rect else { return "nil" }
        return String(format: "(%.0f, %.0f, %.0fx%.0f)", r.minX, r.minY, r.width, r.height)
    }

    // MARK: - 键盘（面板内快捷键）

    private func installKeyMonitor() {
        removeKeyMonitor()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            return Self.handle(event)
        }
    }

    private func removeKeyMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private static func post(_ name: Notification.Name, object: Any? = nil) {
        NotificationCenter.default.post(name: name, object: object)
    }

    private static func handle(_ event: NSEvent) -> NSEvent? {
        let key = Int(event.keyCode)
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])

        switch key {
        case 53: // esc
            post(.phClose); return nil
        case 126: // ↑
            post(.phMoveUp); return nil
        case 125: // ↓
            post(.phMoveDown); return nil
        case 36, 76: // return / enter
            post(.phConfirm); return nil
        case 8 where mods == [.command]: // ⌘C 仅复制
            post(.phCopyOnly); return nil
        case 51 where mods == [.command]: // ⌘⌫ 删除
            post(.phDelete); return nil
        case 35 where mods == [.command]: // ⌘P 置顶
            post(.phPin); return nil
        case 13 where mods == [.command]: // ⌘W 关闭
            post(.phClose); return nil
        default:
            break
        }

        // ⌘1~⌘9 快速粘贴
        if mods == [.command] {
            let digitMap: [Int: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
            if let n = digitMap[key] {
                post(.phQuickPaste, object: n - 1)
                return nil
            }
        }
        return event
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // 我们自己 orderOut 也会触发 resignKey；只在面板确实还可见（焦点被别的应用抢走）时收起
        if panel?.isVisible == true {
            hide()
        }
    }

    func windowWillClose(_ notification: Notification) {
        removeKeyMonitor()
    }
}
