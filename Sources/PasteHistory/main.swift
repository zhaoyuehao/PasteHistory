import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ClipStore.shared
    private let monitor = ClipboardMonitor()
    private let hotKey = HotKeyManager()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        AppTracker.start()
        monitor.start()
        iCloudSync.shared.start()
        WebSyncServer.shared.start()
        if Settings.shared.hotKeyEnabled {
            hotKey.register(id: 1, keyCode: kVK_ANSI_C, carbonModifiers: cmdKey | shiftKey) { [weak self] in
                Task { @MainActor in self?.togglePanel() }
            }
            // ⇧⌘V：不开面板，直接在历史里来回擦
            hotKey.register(id: 2, keyCode: kVK_ANSI_V, carbonModifiers: cmdKey | shiftKey) {
                Task { @MainActor in PasteCycler.shared.advance() }
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
            PanelController.shared.show()
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey.unregisterAll()
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
        // 打开面板视为「我要找东西」，⇧⌘V 的循环会话到此为止
        PasteCycler.shared.end()
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

        let open = NSMenuItem(title: "显示剪贴板历史", action: #selector(togglePanel), keyEquivalent: "C")
        open.keyEquivalentModifierMask = [.command, .shift]
        open.image = Self.menuIcon("clipboard")
        menu.addItem(open)

        menu.addItem(NSMenuItem.separator())

        // 最近复制：内联展示，具体条目在 menuWillOpen 里按 tag 插到这个标题后面
        let recentHeader = NSMenuItem(title: "最近复制", action: nil, keyEquivalent: "")
        recentHeader.isEnabled = false
        recentHeader.tag = Self.recentHeaderTag
        menu.addItem(recentHeader)

        menu.addItem(NSMenuItem.separator())

        let phone = NSMenuItem(title: "手机同步", action: #selector(showQR), keyEquivalent: "")
        phone.image = Self.menuIcon("qrcode")
        menu.addItem(phone)

        // 状态文字走 badge（右对齐），标题保持简短
        let syncItem = NSMenuItem(title: "iCloud 同步", action: #selector(toggleSync), keyEquivalent: "")
        syncItem.image = Self.menuIcon("icloud")
        syncItem.tag = Self.syncMenuItemTag
        menu.addItem(syncItem)

        let axItem = NSMenuItem(title: "自动粘贴权限", action: #selector(requestAX), keyEquivalent: "")
        axItem.image = Self.menuIcon("hand.raised")
        axItem.tag = Self.axMenuItemTag
        menu.addItem(axItem)

        menu.addItem(NSMenuItem.separator())

        let pause = NSMenuItem(title: "暂停自动记录", action: #selector(togglePause(_:)), keyEquivalent: "")
        pause.state = Settings.shared.paused ? .on : .off
        menu.addItem(pause)

        let plain = NSMenuItem(title: "粘贴时不带格式", action: #selector(togglePlainText(_:)), keyEquivalent: "")
        plain.state = Settings.shared.pasteAsPlainText ? .on : .off
        menu.addItem(plain)

        let auto = NSMenuItem(title: "双击或回车直接粘贴", action: #selector(toggleAutoPaste(_:)), keyEquivalent: "")
        auto.state = Settings.shared.autoPaste ? .on : .off
        menu.addItem(auto)

        menu.addItem(NSMenuItem.separator())

        // 记录数统计。必须带 tag 定位：分隔线的 title 也是空字符串，
        // menuWillOpen 里按空 title 反查会误命中分隔线，导致这一行永远空白
        let count = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        count.isEnabled = false
        count.tag = Self.statsMenuItemTag
        menu.addItem(count)

        menu.addItem(NSMenuItem.separator())

        let clear = NSMenuItem(title: "清空历史", action: #selector(clearHistory), keyEquivalent: "")
        clear.image = Self.menuIcon("trash")
        clear.attributedTitle = NSAttributedString(
            string: "清空历史",
            attributes: [.foregroundColor: NSColor.systemRed]
        )
        menu.addItem(clear)

        menu.addItem(NSMenuItem(title: "退出 PasteHistory",
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

    private static let statsMenuItemTag = 9001
    private static let recentHeaderTag = 9002
    private static let syncMenuItemTag = 9003
    private static let axMenuItemTag = 9004
    /// 最近复制条目用 9101…9109 标记，menuWillOpen 时先按 tag 清掉再重插
    private static let recentItemTagBase = 9100

    @objc private func showQR() {
        QRPairPanel.shared.show()
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "清空全部剪贴板记录？"
        alert.informativeText = "共 \(store.count) 条，此操作不可撤销。"
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
        rebuildRecentItems(in: menu)

        if let countItem = menu.item(withTag: Self.statsMenuItemTag) {
            countItem.title = "已保存 \(store.count) 条记录"
        }

        if let syncItem = menu.item(withTag: Self.syncMenuItemTag) {
            let syncOn = Settings.shared.iCloudSync && iCloudSync.shared.isActive
            syncItem.badge = NSMenuItemBadge(string: syncOn ? "已开启"
                                                            : (Settings.shared.iCloudSync ? "未登录" : "已关闭"))
        }

        if let axItem = menu.item(withTag: Self.axMenuItemTag) {
            let trusted = PasteService.isTrusted()
            axItem.badge = NSMenuItemBadge(string: trusted ? "已开启" : "待授权")
        }
    }

    /// 最近 3 条内联在标题下方，⌘1–3 直接粘贴（菜单展开时才响应，不会劫持全局快捷键）
    private func rebuildRecentItems(in menu: NSMenu) {
        for i in 1...9 {
            if let old = menu.item(withTag: Self.recentItemTagBase + i) {
                menu.removeItem(old)
            }
        }
        guard let header = menu.item(withTag: Self.recentHeaderTag) else { return }
        var insertIndex = menu.index(of: header) + 1

        let top = store.recent(3)
        if top.isEmpty {
            let none = NSMenuItem(title: "暂无记录", action: nil, keyEquivalent: "")
            none.isEnabled = false
            none.tag = Self.recentItemTagBase + 1
            menu.insertItem(none, at: insertIndex)
            return
        }
        for (i, item) in top.enumerated() {
            let entry = NSMenuItem(title: String(item.summary.prefix(40)),
                                   action: #selector(pasteRecent(_:)),
                                   keyEquivalent: "\(i + 1)")
            entry.keyEquivalentModifierMask = [.command]
            entry.representedObject = item.id.uuidString
            entry.tag = Self.recentItemTagBase + i + 1
            entry.image = Self.menuIcon(Self.symbol(for: item.kind))
            menu.insertItem(entry, at: insertIndex)
            insertIndex += 1
        }
    }

    private static func symbol(for kind: ClipKind) -> String {
        switch kind {
        case .text: return "doc.text"
        case .image: return "photo"
        case .files: return "folder"
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
