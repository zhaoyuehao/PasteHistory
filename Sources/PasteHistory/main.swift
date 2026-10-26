import AppKit
import Carbon.HIToolbox
import QuartzCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ClipStore.shared
    private let monitor = ClipboardMonitor()
    private let hotKey = HotKeyManager()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserFeedback.present = { message, duration in Toast.show(message, duration: duration) }
        NSApp.setActivationPolicy(.accessory)

        AppTracker.start()
        monitor.start()
        iCloudSync.shared.start()
        WebSyncServer.shared.configurePage(html: WebSyncPage.html)
        WebSyncServer.shared.start()
        if Settings.shared.hotKeyEnabled {
            hotKey.register(id: 1, keyCode: kVK_ANSI_V, carbonModifiers: cmdKey | shiftKey) { [weak self] in
                Task { @MainActor in self?.togglePanel() }
            }
        }

        buildStatusBar()

        NotificationCenter.default.addObserver(
            forName: .pasteHistoryDidWritePasteboard,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.monitor.syncChangeCount() }
        }

        // 捕获成功：菜单栏图标「点头」一下。不弹通知、不出声——
        // 状态灯是给工程师看的，用户只需要感到「它被记住了」
        NotificationCenter.default.addObserver(
            forName: .pasteHistoryDidCapture,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.nodStatusBar() }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.monitor.stop()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.monitor.start()
                // 睡醒后监听常失效，手机会连不上 → 重启一次
                WebSyncServer.shared.restart()
            }
        }

        if !Settings.shared.launchedBefore {
            Settings.shared.launchedBefore = true
            firstRun()
        }

        // 仅供冒烟测试：--show 启动即打开面板
        if ProcessInfo.processInfo.arguments.contains("--show") {
            DispatchQueue.main.async { PanelController.shared.show() }
        }

        // 仅供冒烟测试：--show-pair 启动即打开手机同步配对面板
        if ProcessInfo.processInfo.arguments.contains("--show-pair") {
            QRPairPanel.shared.show()
        }

        // 维护参数：--purge-ids uuid1,uuid2 清除指定记录（本地 DB + iCloud 文件 + 墓碑）
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--purge-ids"), i + 1 < args.count {
            let ids = args[i + 1].split(separator: ",").compactMap { UUID(uuidString: String($0)) }
            for id in ids {
                store.remove(id: id)          // 本地 DB（存在则删）
                iCloudSync.shared.exportDelete(id: id) // iCloud 文件 + 墓碑（无条件清理）
            }
            NSLog("[PasteHistory] purge 完成: \(ids)")
        }

        // 维护参数：--restore-images 从 iCloud 恢复本地缺失的图片原图
        if args.contains("--restore-images") {
            iCloudSync.shared.restoreImages()
        }

        // 冒烟：--print-ax 把辅助功能权限状态写到文件（便于脚本断言）；未授权时弹一次系统对话框
        if args.contains("--print-ax") {
            if !PasteService.isTrusted() {
                _ = PasteService.requestTrust()
            }
            let status = PasteService.isTrusted() ? "trusted" : "not-trusted"
            let out = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/PasteHistory/ax_status.txt")
            try? status.write(to: out, atomically: true, encoding: .utf8)
        }

        // 冒烟：--paste-latest 对最新记录走完整粘贴流程（需前台有聚焦输入框）
        if args.contains("--paste-latest") {
            if let latest = store.recent(1).first {
                let target = AppTracker.targetApp()
                let element = target.flatMap { AXFocus.focusedElement(pid: $0.processIdentifier) }
                PasteService.paste(latest, to: target, focusElement: element)
            }
        }

        // 冒烟：--smoke-panel-paste 复现真实路径（开面板 → 选一条 → 回车粘贴），验证焦点切换
        if args.contains("--smoke-panel-paste") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                PanelController.shared.show()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if let latest = self.store.recent(1).first {
                        PanelController.shared.pasteItem(latest)
                    }
                }
            }
        }

        // 冒烟：--smoke-preview 走空格同款路径（开面板 → 预览开 → ↓跟随 → 预览收），
        // 全程打日志断言；历史里至少要有 2 条记录才能验证「切换跟随」
        if args.contains("--smoke-preview") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                PanelController.shared.show()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    PanelController.shared.togglePreview()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        let opened = PanelController.shared.isPreviewVisible
                        NotificationCenter.default.post(name: .phMoveDown, object: nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            let moved = PanelController.shared.isPreviewVisible
                            PanelController.shared.togglePreview()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                let closed = !PanelController.shared.isPreviewVisible
                                NSLog("[PH] smoke-preview: open=%@ switch-follow=%@ close=%@",
                                      opened ? "OK" : "FAIL",
                                      moved ? "OK" : "FAIL",
                                      closed ? "OK" : "FAIL")
                                PanelController.shared.hide()
                            }
                        }
                    }
                }
            }
        }
    }

    // Opening the installed app again should reveal the overlay even when the
    // menu-bar process is already running (startup arguments aren't replayed).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        PanelController.shared.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey.unregisterAll()
        monitor.stop()
    }

    private func firstRun() {
        if !PasteService.isTrusted() {
            _ = PasteService.requestTrust()
        }
        let alert = NSAlert()
        alert.messageText = L10n.firstRunTitle
        alert.informativeText = L10n.firstRunInfo
        alert.addButton(withTitle: L10n.ok)
        alert.runModal()
    }

    @objc private func togglePanel() {
        PanelController.shared.toggle()
    }

    // MARK: - 菜单栏

    private func buildStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: L10n.clipboardHistoryAccessibility)
            button.toolTip = "\(L10n.panelTitle)（⇧⌘V）"
        }
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let open = NSMenuItem(title: L10n.showClipboard, action: #selector(togglePanel), keyEquivalent: "V")
        open.keyEquivalentModifierMask = [.command, .shift]
        open.image = Self.menuIcon("clipboard")
        menu.addItem(open)
        // 同步只在失败时出现：成功是承诺，不是新闻
        let syncItem = NSMenuItem(title: L10n.iCloudUnsynced, action: #selector(retrySync), keyEquivalent: "")
        syncItem.image = Self.menuIcon("icloud.slash")
        syncItem.tag = Self.syncMenuItemTag
        syncItem.isHidden = true
        menu.addItem(syncItem)

        menu.addItem(NSMenuItem.separator())

        let pause = NSMenuItem(title: L10n.pauseRecording, action: #selector(togglePause(_:)), keyEquivalent: "")
        pause.state = Settings.shared.paused ? .on : .off
        pause.image = Self.menuIcon("pause.circle")
        menu.addItem(pause)

        let clear = NSMenuItem(title: L10n.clearHistory, action: #selector(clearHistory), keyEquivalent: "")
        clear.image = Self.menuIcon("trash")
        clear.attributedTitle = NSAttributedString(
            string: L10n.clearHistory,
            attributes: [.foregroundColor: NSColor.systemRed]
        )
        menu.addItem(clear)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: L10n.quit,
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))

        menu.delegate = self
        return menu
    }

    private static func menuIcon(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.size = NSSize(width: 15, height: 15)
        image?.isTemplate = true
        return image
    }

    private static let syncMenuItemTag = 9003

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = L10n.clearHistoryTitle
        alert.informativeText = L10n.clearHistoryInfo(store.count)
        // 破坏性操作不做回车默认钮：取消在前（Return/Esc 都落在取消上），清空要显式点。
        // 红色沿用菜单里的标识
        alert.addButton(withTitle: L10n.cancel)
        alert.addButton(withTitle: L10n.clear)
        alert.buttons.last?.attributedTitle = NSAttributedString(
            string: L10n.clear,
            attributes: [.foregroundColor: NSColor.systemRed]
        )
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        store.clearAll()
    }

    @objc private func togglePause(_ sender: NSMenuItem) {
        Settings.shared.paused.toggle()
        sender.state = Settings.shared.paused ? .on : .off
    }

    @objc private func retrySync() {
        iCloudSync.shared.start()
    }

    /// 捕获成功：图标「点头」一下，0.30s 内 1→1.15→1
    private func nodStatusBar() {
        guard let button = statusItem?.button else { return }
        button.wantsLayer = true
        let nod = CABasicAnimation(keyPath: "transform.scale")
        nod.fromValue = 1.0
        nod.toValue = 1.15
        nod.duration = 0.15
        nod.autoreverses = true
        nod.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        button.layer?.add(nod, forKey: "nod")
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // 同步正常时这一项根本不存在；只有确实没同步上才开口
        if let syncItem = menu.item(withTag: Self.syncMenuItemTag) {
            syncItem.isHidden = !(Settings.shared.iCloudSync && !iCloudSync.shared.isActive)
        }
    }
}

// MARK: - 入口

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    let app = NSApplication.shared
    app.delegate = delegate
    app.run()
}
