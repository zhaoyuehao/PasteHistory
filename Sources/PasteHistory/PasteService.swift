import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum PasteService {
    // MARK: - 回写剪贴板

    @MainActor
    static func write(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text:
            let text = item.text ?? ""
            // 纯文本粘贴：只写 string，不带富文本/HTML 格式
            if Settings.shared.pasteAsPlainText {
                pb.setString(text, forType: .string)
            } else {
                pb.setString(text, forType: .string)
                if let rtf = item.text, let data = rtf.data(using: .utf8) {
                    pb.setData(data, forType: .rtf)
                }
            }
        case .image:
            if let img = ClipStore.shared.image(named: item.imageFile) {
                pb.writeObjects([img])
            }
        case .files:
            let urls = (item.filePaths ?? []).compactMap { URL(fileURLWithPath: $0) }
            if !urls.isEmpty {
                pb.writeObjects(urls as [NSURL])
            }
        }
    }

    // MARK: - 辅助功能权限（模拟 ⌘V 需要）

    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// 每次启动只弹一次系统授权对话框，避免双击一次弹一次
    private static var promptedThisLaunch = false

    @discardableResult
    static func requestTrust() -> Bool {
        if promptedThisLaunch {
            // 已弹过：不再触发对话框，静默返回当前状态
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        promptedThisLaunch = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - 模拟 ⌘V 粘贴到当前前台应用

    static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        usleep(20_000)
        up.post(tap: .cghidEventTap)
    }

    /// 完整粘贴流程：回写剪贴板 → 切回原应用 → 把焦点放回原输入框 → 发送 ⌘V
    @MainActor
    static func paste(_ item: ClipItem, to app: NSRunningApplication?, focusElement: AXUIElement? = nil) {
        write(item)
        NotificationCenter.default.post(name: .pasteHistoryDidWritePasteboard, object: nil)

        guard Settings.shared.autoPaste else {
            Toast.show("已复制到剪贴板，按 ⌘V 粘贴")
            return
        }

        guard isTrusted() else {
            // 没权限就别静默失败，明确告诉用户内容已经在哪
            Toast.show("已复制到剪贴板，按 ⌘V 粘贴。开启辅助功能权限后可自动填入输入框", duration: 3)
            requestTrust()
            return
        }

        if let app {
            app.activate()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            // 焦点已经切回原输入框，再发 ⌘V，内容才会落到那个输入框里
            if let element = focusElement {
                AXFocus.focus(element)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                sendCommandV()
            }
        }
    }
}

extension Notification.Name {
    static let pasteHistoryDidWritePasteboard = Notification.Name("pasteHistoryDidWritePasteboard")
}
