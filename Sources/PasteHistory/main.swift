import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ClipStore.shared
    private let monitor = ClipboardMonitor()
    private let hotKey = HotKeyManager()
    private var statusItem: NSStatusItem?
    private var recentMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        AppTracker.start()
        monitor.start()
        iCloudSync.shared.start()
        WebSyncServer.shared.start()
        if Settings.shared.hotKeyEnabled {
            hotKey.register { [weak self] in
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
            Task { @MainActor in self?.monitor.start() }
        }

        if !Settings.shared.launchedBefore {
            Settings.shared.launchedBefore = true
            firstRun()
        }

        // 仅供冒烟测试：--show 启动即打开面板
        if ProcessInfo.processInfo.arguments.contains("--show") {
            PanelController.shared.show()
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
            var status = PasteService.isTrusted() ? "trusted" : "not-trusted"
            if status == "not-trusted" {
                _ = PasteService.requestTrust()
            }
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey.unregister()
        monitor.stop()
    }

    private func firstRun() {
        _ = PasteService.requestTrust()
        let alert = NSAlert()
        alert.messageText = "PasteHistory 已在菜单栏运行"
        alert.informativeText = "按 ⇧⌘C（Shift + Command + C）随时打开剪贴板历史，支持搜索。\n\n自动粘贴需要在「系统设置 → 隐私与安全性 → 辅助功能」中允许 PasteHistory；未授权时只会把内容复制到剪贴板，自行按 ⌘V 即可。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func togglePanel() {
        PanelController.shared.toggle()
    }

    // MARK: - 菜单栏

    private func buildStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "剪贴板历史")
            button.toolTip = "剪贴板历史（⇧⌘C）"
        }
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let open = NSMenuItem(title: "打开历史面板", action: #selector(togglePanel), keyEquivalent: "C")
        open.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(open)

        let capture = NSMenuItem(title: "记录当前剪贴板", action: #selector(captureCurrent), keyEquivalent: "")
        menu.addItem(capture)

        let phone = NSMenuItem(title: "手机同步（二维码）…", action: #selector(showQR), keyEquivalent: "")
        menu.addItem(phone)

        menu.addItem(NSMenuItem.separator())

        let recent = NSMenuItem(title: "最近记录", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        recent.submenu = submenu
        menu.addItem(recent)
        recentMenu = submenu

        let clear = NSMenuItem(title: "清空全部历史…", action: #selector(clearHistory), keyEquivalent: "")
        menu.addItem(clear)

        menu.addItem(NSMenuItem.separator())

        let pause = NSMenuItem(title: "暂停记录", action: #selector(togglePause(_:)), keyEquivalent: "")
        pause.state = Settings.shared.paused ? .on : .off
        menu.addItem(pause)

        let plain = NSMenuItem(title: "粘贴为纯文本", action: #selector(togglePlainText(_:)), keyEquivalent: "")
        plain.state = Settings.shared.pasteAsPlainText ? .on : .off
        menu.addItem(plain)

        let auto = NSMenuItem(title: "双击 / 回车自动粘贴到输入框", action: #selector(toggleAutoPaste(_:)), keyEquivalent: "")
        auto.state = Settings.shared.autoPaste ? .on : .off
        menu.addItem(auto)

        menu.addItem(NSMenuItem.separator())

        // iCloud 同步状态
        let syncOn = Settings.shared.iCloudSync && iCloudSync.shared.isActive
        let syncItem = NSMenuItem(
            title: syncOn ? "iCloud 同步：已开启" : (Settings.shared.iCloudSync ? "iCloud 同步：未登录 iCloud Drive" : "iCloud 同步：已关闭"),
            action: #selector(toggleSync),
            keyEquivalent: ""
        )
        menu.addItem(syncItem)

        let trusted = PasteService.isTrusted()
        let axItem = NSMenuItem(
            title: trusted ? "辅助功能权限：已授权" : "请求辅助功能权限…",
            action: trusted ? nil : #selector(requestAX),
            keyEquivalent: ""
        )
        menu.addItem(axItem)

        let count = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        count.isEnabled = false
        menu.addItem(count)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.delegate = self
        return menu
    }

    @objc private func captureCurrent() {
        monitor.captureCurrent()
    }

    @objc private func showQR() {
        QRPairPanel.shared.show()
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "清空全部剪贴板历史？"
        alert.informativeText = "共 \(store.count) 条记录，此操作不可撤销。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.clearAll()
    }

    @objc private func togglePause(_ sender: NSMenuItem) {
        Settings.shared.paused.toggle()
        sender.state = Settings.shared.paused ? .on : .off
    }

    @objc private func togglePlainText(_ sender: NSMenuItem) {
        Settings.shared.pasteAsPlainText.toggle()
        sender.state = Settings.shared.pasteAsPlainText ? .on : .off
    }

    @objc private func toggleAutoPaste(_ sender: NSMenuItem) {
        Settings.shared.autoPaste.toggle()
        sender.state = Settings.shared.autoPaste ? .on : .off
    }

    @objc private func toggleSync() {
        Settings.shared.iCloudSync.toggle()
        if Settings.shared.iCloudSync {
            iCloudSync.shared.start()
        } else {
            iCloudSync.shared.stop()
        }
    }

    @objc private func requestAX() {
        _ = PasteService.requestTrust()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard let submenu = recentMenu else { return }
        submenu.removeAllItems()
        let top = store.recent(10)
        if top.isEmpty {
            submenu.addItem(NSMenuItem(title: "暂无记录", action: nil, keyEquivalent: ""))
        } else {
            for (i, item) in top.enumerated() {
                let title = String(item.summary.prefix(48))
                let menuItem = NSMenuItem(title: title, action: #selector(pasteRecent(_:)), keyEquivalent: "")
                menuItem.representedObject = item.id.uuidString
                if i < 9 {
                    menuItem.keyEquivalent = "\(i + 1)"
                    menuItem.keyEquivalentModifierMask = [.command]
                }
                submenu.addItem(menuItem)
            }
        }
        if let countItem = menu.items.last(where: { $0.title.isEmpty || $0.title.hasPrefix("共 ") }) {
            countItem.title = "共 \(store.count) 条记录（上限 \(Settings.shared.maxItems)）"
        }
    }

    @objc private func pasteRecent(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let id = UUID(uuidString: idString),
              let item = store.syncDatabase.get(id: id) else { return }
        let target = AppTracker.targetApp()
        let element = target.flatMap { AXFocus.focusedElement(pid: $0.processIdentifier) }
        PasteService.paste(item, to: target, focusElement: element)
    }
}

// MARK: - 入口

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    let app = NSApplication.shared
    app.delegate = delegate
    app.run()
}
