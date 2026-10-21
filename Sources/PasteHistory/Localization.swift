import Foundation

/// Native UI copy lives in one place so views and services do not own user-facing text.
/// The language follows macOS's preferred language list on every launch.
enum L10n {
    enum Language {
        case simplifiedChinese
        case traditionalChinese
        case english

        static var system: Language {
            let identifier = (Locale.preferredLanguages.first ?? Locale.current.identifier).lowercased()
            if identifier.hasPrefix("zh-hant") || identifier.hasPrefix("zh-tw") || identifier.hasPrefix("zh-hk") { return .traditionalChinese }
            if identifier.hasPrefix("zh") { return .simplifiedChinese }
            return .english
        }
    }

    static let language = Language.system

    static func value(_ zhHans: String, _ zhHant: String, _ en: String) -> String {
        switch language {
        case .simplifiedChinese: return zhHans
        case .traditionalChinese: return zhHant
        case .english: return en
        }
    }

    static let appName = "PasteHistory"
    static var panelTitle: String { value("剪贴板历史", "剪貼簿歷史", "Clipboard History") }
    static var search: String { value("搜索", "搜尋", "Search") }
    static var clear: String { value("清空", "清除", "Clear") }
    static var showClipboard: String { value("显示剪贴板", "顯示剪貼簿", "Show Clipboard") }
    static var pasteEarlier: String { value("粘贴更早一条", "貼上較早內容", "Paste Earlier") }
    static var phoneSync: String { value("手机同步", "手機同步", "Phone Sync") }
    static var iCloudUnsynced: String { value("iCloud 未同步", "iCloud 未同步", "iCloud Not Synced") }
    static var pauseRecording: String { value("暂停记录", "暫停記錄", "Pause Recording") }
    static var clearHistory: String { value("清空历史…", "清除歷史記錄…", "Clear History…") }
    static var quit: String { value("退出 PasteHistory", "結束 PasteHistory", "Quit PasteHistory") }
    static var clipboardHistoryAccessibility: String { value("剪贴板历史", "剪貼簿歷史", "Clipboard history") }
    static var copyAddress: String { value("复制地址", "複製地址", "Copy Address") }

    static var all: String { value("全部", "全部", "All") }
    static var text: String { value("文本", "文字", "Text") }
    static var image: String { value("图片", "圖片", "Image") }
    static var files: String { value("文件", "檔案", "Files") }
    static var pinned: String { value("置顶", "置頂", "Pinned") }
    static var today: String { value("今天", "今天", "Today") }
    static var yesterday: String { value("昨天", "昨天", "Yesterday") }
    static var earlier: String { value("更早", "更早", "Earlier") }
    static var attachedText: String { value("附带文字", "附帶文字", "Attached text") }
    static var imageText: String { value("图内文字", "圖中文字", "Text in image") }
    static var fileMissing: String { value("原文件已不存在", "原始檔案已不存在", "Original file is missing") }
    static var pinItem: String { value("置顶", "置頂", "Pin") }
    static var deleteItem: String { value("删除", "刪除", "Delete") }
    /// ⌘1–9 角标的读屏名字。「⌘1」念出来没有人听得懂
    static func quickPaste(_ n: Int) -> String {
        value("快速粘贴第 \(n) 条", "快速貼上第 \(n) 筆", "Paste item \(n)")
    }
    static var noHistory: String { value("你的剪贴板还没有记忆。", "你的剪貼簿還沒有記錄。", "Your clipboard history is empty.") }
    static var noMatch: String { value("没找到。", "找不到。", "No matches.") }
    static var copySomething: String { value("⌘C 复制点什么，⇧⌘C 回来", "⌘C 複製內容，再按 ⇧⌘C 回來", "Copy something with ⌘C, then press ⇧⌘C") }
    static var tryAnother: String { value("换个词试试", "換個關鍵字試試", "Try another search") }

    static var phoneSyncSubtitle: String { value("同一 Wi-Fi 下扫码连接", "在同一 Wi-Fi 下掃描連線", "Scan to connect on the same Wi-Fi") }
    static var waitingForNetwork: String { value("等待网络", "等待網路", "Waiting for network") }
    static var pairingCodeHint: String { value("配对码，手机端输入一次即可记住", "配對碼，手機輸入一次即可記住", "Enter this pairing code once on your phone") }
    static var encrypted: String { value("端到端加密 · AES-256-GCM", "端對端加密 · AES-256-GCM", "End-to-end encrypted · AES-256-GCM") }
    static var refreshQRCode: String { value("刷新二维码", "重新整理 QR Code", "Refresh QR Code") }
    static var noNetworkAddress: String { value("未找到局域网地址，请确认 Wi-Fi", "找不到區域網路位址，請確認 Wi-Fi", "No local network address. Check Wi-Fi.") }

    static var firstRunTitle: String { value("PasteHistory 已在菜单栏运行", "PasteHistory 已在選單列執行", "PasteHistory is running in the menu bar") }
    static var firstRunInfo: String {
        value("⇧⌘V 直接粘贴上一条，再按一次换成更早一条；要找东西时按 ⇧⌘C 打开面板搜索。\n\n自动粘贴需要在「系统设置 → 隐私与安全性 → 辅助功能」中允许 PasteHistory；未授权时只会把内容复制到剪贴板，自行按 ⌘V 即可。", "⇧⌘V 直接貼上上一筆，再按一次換成更早一筆；要找內容時按 ⇧⌘C 開啟面板搜尋。\n\n自動貼上需要在「系統設定 → 隱私權與安全性 → 輔助使用」中允許 PasteHistory；未授權時只會將內容複製到剪貼簿，請自行按 ⌘V。", "Press ⇧⌘V to paste the previous item, and press it again for an earlier item. Press ⇧⌘C to search your history.\n\nAutomatic pasting requires PasteHistory to be allowed in System Settings → Privacy & Security → Accessibility. Without access, the item is copied to the clipboard so you can press ⌘V yourself.")
    }
    static var ok: String { value("好", "好", "OK") }
    static var clearHistoryTitle: String { value("清空全部剪贴板记录？", "清除全部剪貼簿記錄？", "Clear all clipboard history?") }
    static func clearHistoryInfo(_ count: Int) -> String { value("共 \(count) 条，此操作不可撤销。", "共 \(count) 筆，此操作無法復原。", "\(count) items. This cannot be undone.") }
    static var cancel: String { value("取消", "取消", "Cancel") }
    static var pasteToClipboard: String { value("已复制到剪贴板，按 ⌘V 粘贴", "已複製到剪貼簿，按 ⌘V 貼上", "Copied to clipboard. Press ⌘V to paste.") }
    static var pastePermissionHint: String { value("已复制到剪贴板，按 ⌘V 粘贴。开启自动粘贴权限后可免按 ⌘V", "已複製到剪貼簿，按 ⌘V 貼上。開啟自動貼上權限後可免按 ⌘V", "Copied to clipboard. Press ⌘V to paste. Grant Accessibility access to paste automatically.") }
    static var noClipboardHistory: String { value("剪贴板里还没有记录", "剪貼簿裡還沒有記錄", "There is no clipboard history yet") }
    static var remoteClipboard: String { value("接力 · iPhone/iPad", "接力 · iPhone/iPad", "Handoff · iPhone/iPad") }
    static var phoneWeb: String { value("手机网页", "手機網頁", "Phone web page") }
    static func portBusy(_ port: UInt16) -> String { value("端口 \(port) 被占用，手机连不上（换端口或退出占用程序后重启本应用）", "連接埠 \(port) 已被使用，手機無法連線（請更換連接埠或退出佔用程式後重啟）", "Port \(port) is already in use. Restart after changing the port or quitting the other app.") }
    static func imageSummary(_ text: String?) -> String { guard let text, !text.isEmpty else { return image }; return value("图片 · ", "圖片 · ", "Image · ") + text }
    static func fileSummary(count: Int, names: [String]) -> String { if count == 1 { return names.first ?? files }; return "\(count)" + value("个文件：", "個檔案：", " files: ") + names.prefix(3).joined(separator: value("、", "、", ", ")) }
    static func moreFiles(_ count: Int) -> String { value("还有 \(count) 个", "還有 \(count) 個", "\(count) more") }
    static func minutesAgo(_ count: Int) -> String { value("\(count) 分钟前", "\(count) 分鐘前", "\(count) min ago") }
    static func todayAt(_ time: String) -> String { value("今天 \(time)", "今天 \(time)", "Today \(time)") }
    static func yesterdayAt(_ time: String) -> String { value("昨天 \(time)", "昨天 \(time)", "Yesterday \(time)") }
}
