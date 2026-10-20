import AppKit
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
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let shared = PanelController()

    private var panel: NSPanel?
    private var localMonitor: Any?
    private var previousApp: NSRunningApplication?
    /// 唤起面板前系统里聚焦的那个输入框，粘贴后要把焦点还回去
    private var previousFocusElement: AXUIElement?
    private let store = ClipStore.shared
    /// 每次 show/hide 递增：作废仍在排队的"延迟切回原应用"，防止它把刚打开的面板再次打掉
    private var showGeneration = 0

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        if panel == nil { buildPanel() }
        guard let panel else { return }
        // 作废上一次 hide() 排队的 previousApp.activate()：
        // 否则快速收起后再按 ⇧⌘C，那个延迟激活会把面板顶掉 → resignKey → 面板立刻又消失
        showGeneration += 1

        // 打开面板时顺手对账一次 iCloud 远端变化
        iCloudSync.shared.importAll()

        // 记住唤起面板前的前台应用和它当前聚焦的输入框，粘贴时要原样还回去
        let target = AppTracker.targetApp()
        previousApp = target
        previousFocusElement = target.flatMap { AXFocus.focusedElement(pid: $0.processIdentifier) }

        center(panel)
        installKeyMonitor()
        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate()
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        showGeneration += 1
        let generation = showGeneration
        removeKeyMonitor()
        panel.orderOut(nil)
        if let app = previousApp {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                // 期间又 show() 过（面板可见）就不抢焦点
                guard let self, self.showGeneration == generation,
                      !(self.panel?.isVisible ?? false) else { return }
                app.activate()
            }
        }
    }

    // MARK: - 构建

    private func buildPanel() {
        let view = HistoryView(
            store: store,
            onPaste: { [weak self] item in
                guard let self else { return }
                let target = previousApp
                let element = previousFocusElement
                hide()
                PasteService.paste(item, to: target, focusElement: element)
            },
            onCopyOnly: { [weak self] item in
                guard let self else { return }
                hide()
                PasteService.write(item)
                NotificationCenter.default.post(name: .pasteHistoryDidWritePasteboard, object: nil)
            },
            onClose: { [weak self] in self?.hide() }
        )

        let hosting = NSHostingController(rootView: view)
        let panel = NSPanel(contentViewController: hosting)
        panel.styleMask = [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel]
        panel.title = "剪贴板历史"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.setContentSize(NSSize(width: 760, height: 520))
        panel.minSize = NSSize(width: 620, height: 380)
        panel.delegate = self
        self.panel = panel
    }

    private func center(_ panel: NSPanel) {
        // 显示在鼠标所在的屏幕，更符合剪贴板工具的使用习惯
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.maxY - size.height - 60
        panel.setFrameOrigin(NSPoint(x: x, y: max(y, visible.minY + 20)))
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
