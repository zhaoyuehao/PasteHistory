import Foundation

// MARK: - 设置

final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let maxItems = "maxItems"
        static let paused = "paused"
        static let pasteAsPlainText = "pasteAsPlainText"
        static let hotKeyEnabled = "hotKeyEnabled"
        static let autoPaste = "autoPaste"
        static let launchedBefore = "launchedBefore"
        static let ignoredApps = "ignoredApps"
        static let iCloudSync = "iCloudSyncEnabled"
        static let iCloudInitialExport = "iCloudInitialExportDone"
        static let machineId = "syncMachineId"
        static let anchorPanel = "anchorPanelToInput"
        static let panelWidth = "panelWidth"
        static let panelHeight = "panelHeight"
    }

    var maxItems: Int {
        get { let v = defaults.integer(forKey: Key.maxItems); return v <= 0 ? 500 : v }
        set { defaults.set(newValue, forKey: Key.maxItems) }
    }

    var paused: Bool {
        get { defaults.bool(forKey: Key.paused) }
        set { defaults.set(newValue, forKey: Key.paused) }
    }

    var pasteAsPlainText: Bool {
        get { defaults.object(forKey: Key.pasteAsPlainText) == nil ? true : defaults.bool(forKey: Key.pasteAsPlainText) }
        set { defaults.set(newValue, forKey: Key.pasteAsPlainText) }
    }

    var autoPaste: Bool {
        get { defaults.object(forKey: Key.autoPaste) == nil ? true : defaults.bool(forKey: Key.autoPaste) }
        set { defaults.set(newValue, forKey: Key.autoPaste) }
    }

    var hotKeyEnabled: Bool {
        get { defaults.object(forKey: Key.hotKeyEnabled) == nil ? true : defaults.bool(forKey: Key.hotKeyEnabled) }
        set { defaults.set(newValue, forKey: Key.hotKeyEnabled) }
    }

    var launchedBefore: Bool {
        get { defaults.bool(forKey: Key.launchedBefore) }
        set { defaults.set(true, forKey: Key.launchedBefore) }
    }

    /// 面板贴着唤起它的输入框出现（默认开）。
    /// 粘贴的终点永远是输入框，视线已经在那里了，不该再被拉到屏幕中央。
    var anchorPanel: Bool {
        get { defaults.object(forKey: Key.anchorPanel) == nil ? true : defaults.bool(forKey: Key.anchorPanel) }
        set { defaults.set(newValue, forKey: Key.anchorPanel) }
    }

    /// 面板尺寸：用户拖边调整后的选择。未存过（0）→ φ 默认 400×647（与 Theme.Panel 一致）。
    /// 读时夹回可调范围，防外部写入越界
    var panelWidth: CGFloat {
        get { let v = defaults.double(forKey: Key.panelWidth); return v <= 0 ? 400 : min(max(v, 340), 940) }
        set { defaults.set(newValue, forKey: Key.panelWidth) }
    }

    var panelHeight: CGFloat {
        get { let v = defaults.double(forKey: Key.panelHeight); return v <= 0 ? 647 : min(max(v, 360), 1200) }
        set { defaults.set(newValue, forKey: Key.panelHeight) }
    }

    /// iCloud 同步开关（默认开；未登录 iCloud Drive 时自动无效）
    var iCloudSync: Bool {
        get { defaults.object(forKey: Key.iCloudSync) == nil ? true : defaults.bool(forKey: Key.iCloudSync) }
        set { defaults.set(newValue, forKey: Key.iCloudSync) }
    }

    var iCloudInitialExportDone: Bool {
        get { defaults.bool(forKey: Key.iCloudInitialExport) }
        set { defaults.set(newValue, forKey: Key.iCloudInitialExport) }
    }

    /// 本机稳定标识，避免把 iCloud 里自己导出的记录再导入一遍
    var machineId: String {
        if let existing = defaults.string(forKey: Key.machineId) { return existing }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: Key.machineId)
        return fresh
    }

    var ignoredApps: [String] {
        get { defaults.stringArray(forKey: Key.ignoredApps) ?? defaultIgnoredApps }
        set { defaults.set(newValue, forKey: Key.ignoredApps) }
    }

    let defaultIgnoredApps = [
        "com.agilebits.onepassword",
        "com.1password.1password",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.apple.keychainaccess",
    ]

    func isIgnored(bundleIdentifier: String?) -> Bool {
        guard let id = bundleIdentifier else { return false }
        return ignoredApps.contains(id)
    }
}
