# PasteHistory

macOS 剪贴板历史管理器：后台常驻（菜单栏），自动记录每一次 ⌘C 复制，按 ⇧⌘C 唤起搜索面板，回车即粘贴到当前输入框。SQLite 持久化 + 图片 OCR 索引 + iCloud 多设备同步。

## 存储

- **数据库**：`~/Library/Application Support/PasteHistory/history.sqlite`（WAL 模式），每条记录即时落盘，重启不丢
- **图片原图**：`~/Library/Application Support/PasteHistory/images/`（内容 hash 命名，天然去重）
- **缩略图**：128px PNG 直接存 DB，列表渲染不碰原图
- **内存**：只驻留当前展示页（60 条/页，滚动加载下一页）+ NSCache 限量的图片预览缓存；实测常驻 RSS ~40MB
- 旧版 JSON 首次启动自动迁移（`history.json` → `history.sqlite`，原文件改名 `.migrated` 保留）

## 搜索（简单索引服务）

- 文本 / 文件路径 / 来源应用：SQLite `search_text` 列（小写全文），子串匹配，中文友好（无分词依赖）
- **图片：Vision OCR 后台识别文字**（`.accurate` 模式，简体/繁体中文 + 英文；`.fast` 模式不支持中文，会输出乱码），识别结果进 `search_text`，搜"截图里的文字"能命中；列表摘要直接显示 OCR 提取的文字
- **图片场景分类**：VNClassifyImageRequest 本地语义标签（document/screenshot/receipt 等）进搜索索引——注意这是"分类"不是"理解"，识别不了"这是两只猫"这类内容；语义描述需要多模态大模型（本地 Vision 无此能力，接云端 LLM 则图片内容会离开本机，默认不做）
- 搜索防抖 250ms，直接打 SQL，不扫内存

## 接力（Handoff / 通用剪贴板）支持

- **iPhone/iPad 复制的内容会被自动记录**：接力内容到达 Mac 剪贴板时（同 Apple ID + 蓝牙 + Wi-Fi，约 2 分钟窗口内），轮询即捕获入库，不需要你先手动粘贴
- 通过 Apple 私有类型 `com.apple.is-remote-clipboard` 识别接力来源，记录显示为 **"接力 · iPhone/iPad"**，可按"接力"搜索
- 遵循 [nspasteboard.org](http://nspasteboard.org/) 行业约定：
  - 保密标记（`org.nspasteboard.ConcealedType` / 1Password）→ 不记录
  - 瞬态标记（TextExpander/Butler 等临时中转）→ 不记录

## 手机同步（PWA，零安装）

任何手机/平板（iPhone/Android/iPad）浏览器访问即可双向同步，无需装 App、无需开发者账号：

- **入口**：菜单栏 → "手机同步（二维码）"，扫码打开（或手动访问 `http://<Mac的IP>:8377`）
- **配对码**：6 位数字，首次扫码自动配对（含在二维码 URL 里），也可手动输入
- **端到端加密**：不用 TLS（自签证书会弹浏览器警告），而是配对码 HKDF 派生 AES-256-GCM 密钥，记录内容全部密文传输/存储——同 Wi-Fi 抓包只能看到乱码；鉴权 token = SHA256(配对码)
- **手机 → Mac**：打开网页 → 点"同步剪贴板"→ 浏览器读当前剪贴板（系统会弹一次确认）→ 加密上传入库
- **Mac → 手机**：网页里搜索（含 OCR 文字）→ 点条目查看 → 一键复制 → 去目标 App 粘贴
- **添加到主屏幕**即成 PWA（全屏、有图标）
- 服务线程模型：HTTP 处理在独立网络队列，不经过主线程（菜单打开/弹窗不会卡死服务）；读走独立 SQLite 连接（WAL 并发读），写异步派发主队列
- 仅限同一 Wi-Fi；公共电脑上勿用

## iCloud 同步（多台 Mac）

- 记录以**一记录一文件**写入 iCloud Drive：`iCloud Drive/PasteHistory/clips/<uuid>.json`（确定性文件名，无冲突）；删除写 `tombstones/<uuid>.json`
- 变更监听：NSMetadataQuery 推送 + 60 秒对账兜底 + 打开面板时对账
- 同一 Apple ID 的所有 Mac 互通：A 机复制 → B 机搜索/粘贴；图片文件本体同步过去；OCR 结果随记录同步（B 机不重复识别）
- 菜单栏可开关；未登录 iCloud Drive 自动停用
- **iOS 限制（系统级，无解）**：iPhone/iPad 不允许第三方 app 后台读剪贴板（iOS 9 起禁止后台读、iOS 16 起每次读需用户确认），所以"iPhone 上的历史"做不了自动记录；iOS 端若要做，只能走手动入库（UIPasteControl / Share Sheet / Shortcuts），且需 Apple Developer 账号正式签名。同步协议（一记录一文件 JSON）已是开放格式，iOS 客户端将来可直接对接

## 快捷键

| 快捷键 | 作用 |
| --- | --- |
| ⇧⌘C | 打开 / 关闭历史面板（全局） |
| ↑ ↓ | 移动选择 |
| ⏎ / 双击 | 粘贴到系统当前聚焦的输入框 |
| ⌘C | 仅复制到剪贴板 |
| ⌘1~9 | 快速粘贴前 9 条 |
| ⌘P | 置顶 / 取消置顶 |
| ⌘⌫ | 删除选中项 |
| esc / ⌘W / 点击面板外 | 关闭面板 |

## 权限

- **辅助功能**（系统设置 → 隐私与安全性 → 辅助功能）：自动粘贴（模拟 ⌘V）需要；未授权时回车只进剪贴板并弹提示
- 默认忽略 1Password / Bitwarden / KeePassXC / 钥匙串访问 的复制内容

## 构建与维护

```bash
./scripts/build_app.sh     # 构建 + 打包 + ad-hoc 签名
open PasteHistory.app      # 启动

# 维护：清除指定记录（本地 DB + iCloud 文件 + 墓碑）
open PasteHistory.app --args --purge-ids "uuid1,uuid2"

# 维护：从 iCloud 恢复本地缺失的图片原图
open PasteHistory.app --args --restore-images
```

## 结构

```
Sources/PasteHistory/
├── main.swift             # 入口 + AppDelegate + 菜单栏 + --purge-ids 维护参数
├── Models.swift           # ClipItem 模型、内容指纹、搜索文本列
├── HistoryDatabase.swift  # SQLite 层：WAL、分页查询、upsert 去重、OCR 更新
├── ClipStore.swift        # 门面：分页状态、图片落盘/缩略图、Settings
├── ClipboardMonitor.swift # 轮询 NSPasteboard 捕获文本/图片/文件
├── OCRIndexer.swift       # Vision OCR 后台索引图片文字
├── iCloudSync.swift       # iCloud Drive 事件文件导出/导入合并 + NSMetadataQuery
├── HotKeyManager.swift    # Carbon 全局热键 ⇧⌘C
├── PanelController.swift  # 浮动面板 + 键盘事件分发
├── HistoryView.swift      # 搜索框 + 分页列表 + 预览（SwiftUI）
├── AXFocus.swift          # AX 聚焦输入框的捕获/恢复 + 目标应用跟踪
├── Toast.swift            # 无权限提示条
└── PasteService.swift     # 回写剪贴板 + 恢复焦点 + 模拟 ⌘V
```

自定义热键：改 `HotKeyManager.register(keyCode:carbonModifiers:)` 参数（kVK_ANSI_* + cmdKey/shiftKey/optionKey/controlKey）。
