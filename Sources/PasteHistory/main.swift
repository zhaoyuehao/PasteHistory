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
        NSApp.setActivationPolicy(.accessory)

        AppTracker.start()
        monitor.start()
        iCloudSync.shared.start()
        WebSyncServer.shared.start()
        if Settings.shared.hotKeyEnabled {
            hotKey.register(id: 1, keyCode: kVK_ANSI_C, carbonModifiers: cmdKey | shiftKey) { [weak self] in
                Task { @MainActor in self?.togglePanel() }
            }
            // ⇧⌘V：不开面板，直接在时间轴上擦。再按一次撤销、换成更早一条
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
        alert.informativeText = "⇧⌘V 直接粘贴上一条，再按一次换成更早一条；要找东西时按 ⇧⌘C 打开面板搜索。\n\n自动粘贴需要在「系统设置 → 隐私与安全性 → 辅助功能」中允许 PasteHistory；未授权时只会把内容复制到剪贴板，自行按 ⌘V 即可。"
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

        let open = NSMenuItem(title: "显示剪贴板", action: #selector(togglePanel), keyEquivalent: "C")
        open.keyEquivalentModifierMask = [.command, .shift]
        open.image = Self.menuIcon("clipboard")
        menu.addItem(open)

        let cycle = NSMenuItem(title: "粘贴更早一条", action: #selector(cyclePaste), keyEquivalent: "V")
        cycle.keyEquivalentModifierMask = [.command, .shift]
        cycle.image = Self.menuIcon("clock.arrow.circlepath")
        menu.addItem(cycle)

        menu.addItem(NSMenuItem.separator())

        let phone = NSMenuItem(title: "手机同步", action: #selector(showQR), keyEquivalent: "")
        phone.image = Self.menuIcon("qrcode")
        menu.addItem(phone)

        // 同步只在失败时出现：成功是承诺，不是新闻
        let syncItem = NSMenuItem(title: "iCloud 未同步", action: #selector(retrySync), keyEquivalent: "")
        syncItem.image = Self.menuIcon("icloud.slash")
        syncItem.tag = Self.syncMenuItemTag
        syncItem.isHidden = true
        menu.addItem(syncItem)

        menu.addItem(NSMenuItem.separator())

        let pause = NSMenuItem(title: "暂停记录", action: #selector(togglePause(_:)), keyEquivalent: "")
        pause.state = Settings.shared.paused ? .on : .off
        menu.addItem(pause)

        let clear = NSMenuItem(title: "清空历史…", action: #selector(clearHistory), keyEquivalent: "")
        clear.image = Self.menuIcon("trash")
        clear.attributedTitle = NSAttributedString(
            string: "清空历史…",
            attributes: [.foregroundColor: NSColor.systemRed]
        )
        menu.addItem(clear)

        menu.addItem(NSMenuItem.separator())

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

    private static let syncMenuItemTag = 9003

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

    @objc private func cyclePaste() {
        PasteCycler.shared.advance()
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
