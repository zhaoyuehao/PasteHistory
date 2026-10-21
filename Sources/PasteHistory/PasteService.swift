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
            // 图文记录：文字一并写回剪贴板，目标应用按需取图或取字
            if let text = item.text, !text.isEmpty {
                pb.setString(text, forType: .string)
            }
        case .files:
            let paths = item.filePaths ?? []
            let urls = paths.compactMap { URL(fileURLWithPath: $0) }
            if !urls.isEmpty {
                pb.writeObjects(urls as [NSURL])
            }
            // 同时写一份路径文本：目标是输入框（而非 Finder）时，剪贴板里得有 string 才粘得出东西。
            // fileURL 类型不受影响，Finder 里 ⌘V 仍然粘贴文件本身。
            if !paths.isEmpty {
                pb.setString(paths.joined(separator: "\n"), forType: .string)
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

    /// 撤销上一步（⇧⌘V 循环粘贴时用它撤回刚贴进去的内容）。
    /// 安全前提：栈顶一定是我们刚刚发出的那次 ⌘V——写剪贴板不进目标应用的 undo 栈。
    static func sendCommandZ() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(kVK_ANSI_Z)
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
            Toast.show("已复制到剪贴板，按 ⌘V 粘贴。开启自动粘贴权限后可免按 ⌘V", duration: 3)
            requestTrust()
            return
        }

        NSLog("[PH] paste: trusted=%d autoPaste=%d target=%@ frontmost=%@",
              isTrusted(), Settings.shared.autoPaste,
              app?.localizedName ?? "nil", Self.frontmostName())

        if let app {
            app.activate()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            // 焦点已经切回原输入框，再发 ⌘V，内容才会落到那个输入框里
            NSLog("[PH] paste: 0.25s 后 frontmost=%@（目标 %@）focusElement=%@",
                  Self.frontmostName(), app?.localizedName ?? "nil", focusElement == nil ? "nil" : "有")
            if let element = focusElement {
                NSLog("[PH] paste: AXFocus.focus -> %d", AXFocus.focus(element))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSLog("[PH] paste: 发 ⌘V，此刻 frontmost=%@", Self.frontmostName())
                sendCommandV()
            }
        }
    }

    private static func frontmostName() -> String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil"
    }
}

extension Notification.Name {
    static let pasteHistoryDidWritePasteboard = Notification.Name("pasteHistoryDidWritePasteboard")
}
