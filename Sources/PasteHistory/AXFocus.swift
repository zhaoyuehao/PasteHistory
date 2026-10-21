import AppKit
import CoreGraphics

/// 用 Accessibility API 定位/恢复"当前选中的输入框"
enum AXFocus {
    /// 指定进程里当前聚焦的 UI 元素（输入框、文本区域等）
    static func focusedElement(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value)
        guard result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// 让某个元素重新拿到键盘焦点（切回应用后把光标放回原来的输入框）
    @discardableResult
    static func focus(_ element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
    }

    /// 兜底：直接改写元素当前选区（⌘V 被目标应用吞掉时使用）
    @discardableResult
    static func setSelectedText(_ element: AXUIElement, _ text: String) -> Bool {
        AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success
    }

    /// 元素当前的值，用于校验是否真的贴进去了
    static func value(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let value else { return nil }
        return value as? String
    }

    /// 只有真正的输入框才值得把面板贴过去：focusedElement 常常返回窗口 / 容器，
    /// 贴上去等于贴到半个屏幕
    static func isTextInput(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXRole" as CFString, &value) == .success,
              let role = value as? String else { return false }
        return ["AXTextField", "AXTextArea", "AXSecureTextField", "AXComboBox", "AXSearchField"]
            .contains(role)
    }

    /// 光标（插入点）在屏幕上的位置：你真正在看的位置。
    ///
    /// 文本区常常半屏高，把面板贴到整个文本区必挡正文；贴到光标所在的那一行，
    /// 才是 IME 候选窗那种「贴着指尖」的感觉。取法：选中范围（无选区时即插入点）→
    /// 该范围的屏幕 bounds。不是所有应用都支持这个参数化属性，返回 nil 就退回整框。
    static func caretFrame(of element: AXUIElement) -> CGRect? {
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXSelectedTextRange" as CFString, &rangeValue) == .success,
              let rangeValue,
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }
        var boundsValue: CFTypeRef?
        // 参数化属性名是 AXBoundsForRange（取 CFRange 的屏幕 bounds），不是 AXBoundsForTextRange
        guard AXUIElementCopyParameterizedAttributeValue(element,
                                                         "AXBoundsForRange" as CFString,
                                                         rangeValue,
                                                         &boundsValue) == .success,
              let boundsValue,
              CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else { return nil }
        return rect.height > 2 ? rect : nil
    }

    /// 元素在屏幕上的位置与大小，用于把面板贴到输入框旁边。
    /// 返回的是 AX 坐标系：原点在主屏左上角、y 向下。
    static func frame(of element: AXUIElement) -> CGRect? {
        var value: CFTypeRef?
        // kAXFrameAttribute 没有导出到 Swift，用属性名字符串
        guard AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect) else { return nil }
        return rect
    }
}

/// 记录"上一个非本应用的前台应用"，避免从菜单栏打开时把焦点还给错误的对象
enum AppTracker {
    static var lastExternalApp: NSRunningApplication?

    static func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            lastExternalApp = app
        }
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastExternalApp = front
        }
    }

    /// 唤起面板时的目标应用：优先当前前台，其次是最近一次的外部应用
    static func targetApp() -> NSRunningApplication? {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            return front
        }
        return lastExternalApp
    }
}
