import Carbon.HIToolbox
import Foundation

/// 全局热键：默认 ⇧⌘C 唤起历史面板
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var callback: (() -> Void)?

    private static let signature: OSType = 0x50485354 // PHST

    /// keyCode 用 kVK_ANSI_* 常量，carbonModifiers 用 cmdKey / shiftKey / optionKey / controlKey
    func register(keyCode: Int = kVK_ANSI_C, carbonModifiers: Int = cmdKey | shiftKey, onFire: @escaping () -> Void) {
        unregister()
        callback = onFire

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.callback?() }
            return noErr
        }, 1, &eventType, selfPtr, &eventHandlerRef)

        let hotKeyID = EventHotKeyID(signature: HotKeyManager.signature, id: 1)
        let status = RegisterEventHotKey(UInt32(keyCode),
                                         UInt32(carbonModifiers),
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &hotKeyRef)
        if status != noErr {
            NSLog("[PasteHistory] 注册热键失败: \(status)")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        callback = nil
    }

    deinit { unregister() }
}
