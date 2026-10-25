import Carbon.HIToolbox
import Foundation

/// 全局热键：一个进程内可注册多个，按 EventHotKeyID.id 分发
final class HotKeyManager {
    /// id → 已注册的 Carbon 热键引用
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    /// id → 触发回调
    private var callbacks: [UInt32: () -> Void] = [:]
    private var eventHandlerRef: EventHandlerRef?

    private static let signature: OSType = 0x50485354 // PHST

    /// keyCode 用 kVK_ANSI_* 常量，carbonModifiers 用 cmdKey / shiftKey / optionKey / controlKey
    func register(id: UInt32, keyCode: Int, carbonModifiers: Int, onFire: @escaping () -> Void) {
        unregister(id: id)
        callbacks[id] = onFire
        installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: HotKeyManager.signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode),
                                         UInt32(carbonModifiers),
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        guard status == noErr, let ref else {
            NSLog("[PasteHistory] 注册热键 \(id) 失败: \(status)")
            return
        }
        hotKeyRefs[id] = ref
    }

    func unregister(id: UInt32) {
        if let ref = hotKeyRefs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        callbacks.removeValue(forKey: id)
    }

    func unregisterAll() {
        for id in Array(hotKeyRefs.keys) { unregister(id: id) }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr, hotKeyID.signature == HotKeyManager.signature else { return noErr }

            let id = hotKeyID.id
            DispatchQueue.main.async { manager.callbacks[id]?() }
            return noErr
        }, 1, &eventType, selfPtr, &eventHandlerRef)
    }

    deinit { unregisterAll() }
}
