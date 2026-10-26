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
