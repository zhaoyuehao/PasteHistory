# PasteHistory

macOS 剪贴板历史管理器：后台常驻（菜单栏），自动记录每一次 ⌘C 复制，按 ⇧⌘V 唤起搜索面板，回车即粘贴到当前输入框。SQLite 持久化 + 图片 OCR 索引 + iCloud 多设备同步。

## 3D 许愿树

按 `⇧⌘V` 唤起透明桌面许愿树：象牙白树体直接浮在桌面上，搜索融入树根悬签。每页 8 张纸签系在真实枝头，输入即筛选记录，↑↓ 选择，空格预览，回车粘贴；Page Up / Page Down（MacBook 上 fn↑ / fn↓）翻组。⌘C 复制、⌘P 置顶、Delete 删除，⌘L 可切回列表。日常模式锁定树的位置、大小与视角；菜单栏“调整树布局…”或 ⇧⌘M 进入调整模式，专用把手移动，小／标准／大切换尺寸，完成或 Esc 退出。树体与空白不拦截后方 App 的点击。纸签可直接拖出文字、图片或文件到支持对应格式的 App，只复制、不移动原文件，也不改写系统剪贴板。预览以所选纸签的挂孔为锚点，带轻微回弹展开成同款黄金比例纸面，关闭时收回；方向键切换保持纸面尺寸。唤起时树从根部生长，翻页时纸签快速翻转。[预览与资源维护](docs/ivory-tree/README.md)。

## 存储

- **数据库**：`~/Library/Application Support/PasteHistory/history.sqlite`（WAL 模式），每条记录即时落盘，重启不丢
- **图片原图**：`~/Library/Application Support/PasteHistory/images/`（内容 hash 命名，天然去重）
- **缩略图**：128px PNG 直接存 DB，列表渲染不碰原图
- **内存**：只驻留当前展示页（60 条/页，滚动加载下一页）+ NSCache 限量的图片预览缓存；实测常驻 RSS ~40MB
- 旧版 JSON 首次启动自动迁移（`history.json` → `history.sqlite`，原文件改名 `.migrated` 保留）

## 搜索（简单索引服务）

- 文本 / 文件路径 / 来源应用：SQLite `search_text` 列（小写全文），子串匹配，中文友好（无分词依赖）
- **图片：Vision OCR 后台识别文字**（`.accurate` 模式，简体/繁体中文 + 英文；`.fast` 模式不支持中文，会输出乱码），识别结果进 `search_text`，搜"截图里的文字"能命中；默认显示图片，向下滚动预览可阅读 OCR 文字
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
| ⇧⌘V | 打开 / 关闭历史面板（全局） |
| ⌘L | 列表 / 3D 许愿树 |
| Page Up / Page Down（fn↑ / fn↓） | 许愿树翻组 |
| 空格 | 树模式直接预览当前搜索结果；Shift＋空格输入搜索词中的空格（列表模式保持原行为） |
| ⌘Y | 随时预览 |
| ⇧⌘M | 进入／退出树布局调整；调整期间 ⌘R 复位 |
| ↑ ↓ | 移动选择 |
| ⏎ | 粘贴到系统当前聚焦的输入框 |
| 单击卡片 | 预览（树和列表均适用） |
| 拖动纸签 | 将内容复制投放到支持对应格式的 App；Esc 取消，不移动树 |
| ⌘C | 仅复制到剪贴板 |
| ⌘1~9 | 快速粘贴前 9 条 |
| ⌘P | 置顶 / 取消置顶 |
| Delete | 删除选中项；编辑搜索词时删字 |
| esc / ⌘W / 点击面板外 | 关闭面板 |

## 权限

- **辅助功能**（系统设置 → 隐私与安全性 → 辅助功能）：自动粘贴（模拟 ⌘V）需要；未授权时回车只进剪贴板并弹提示
- 默认忽略 1Password / Bitwarden / KeePassXC / 钥匙串访问 的复制内容

## 构建与维护

```bash
./scripts/build_app.sh     # 构建 + 打包 + Apple Development 签名
open PasteHistory.app      # 启动

# 维护：清除指定记录（本地 DB + iCloud 文件 + 墓碑）
open PasteHistory.app --args --purge-ids "uuid1,uuid2"

# 维护：从 iCloud 恢复本地缺失的图片原图
open PasteHistory.app --args --restore-images
```

## 结构

```
Sources/PasteHistory/
├── main.swift                    # 组合入口：连接服务、界面和用户提示
├── Domain/Models.swift           # 记录、指纹、检索字段；不依赖 UI
├── Application/                  # ClipStore、Settings、HistoryViewModel、键盘规则
├── Infrastructure/
│   ├── Persistence/              # SQLite 查询与写入
│   ├── Clipboard/                # 捕获、复制/粘贴、拖放数据、焦点与热键
│   ├── Media/                    # OCR、原图读取/降采样/缓存
│   ├── Sync/                     # iCloud 与 HTTP 同步
│   └── Diagnostics/              # 定位日志落盘
├── Presentation/
│   ├── Tree/                     # 树体、纸签、挂点、输入窗口
│   ├── History/                  # 列表与搜索布局
│   ├── Preview/                  # 预览窗口与内容布局
│   ├── Animation/                # 阻尼令牌、树动效参数、纸面开合、选中动效适配
│   ├── Style/                    # 字体、间距、颜色、黄金比例
│   ├── Shared/                   # 展示摘要、缩略图适配、提示条
│   ├── Windows/                  # 窗口生命周期与输入路由
│   └── Sync/                     # 配对界面与手机网页
├── Shared/Localization.swift     # 各层共用文案
└── Resources/ivory_tree.scn       # 3D 资源
```

界面通过 `HistoryViewModel` 发起选择、置顶、删除，通过 `ClipStore` 查询和变更记录。状态层只发布状态和输入时序，不导入 SwiftUI、不调用动画；`Presentation/Animation` 根据时序选择阻尼，视图负责应用。数据库、剪贴板载荷、OCR 搜索索引和同步协议与视觉布局独立。

图片纸签以完整缩略图为主体，保持长宽比，不用 OCR 替代图片。OCR 仍参与搜索；展开预览首屏仍只显示图片，下滑后才显示 13pt、可选择的识别文字。图片和文字预览支持原生双指缩放（50%–400%），切换记录或重新打开时重置缩放和滚动位置。无缩略图时显示图片占位，不回退成 OCR 卡片。展开和收回沿用挂孔锚点、黄金矩形与可打断阻尼动画。

预览的文件读取、降采样和缓存由 `Infrastructure/Media/PreviewMediaLoader` 承担，构造时传入当前数据目录；视图不引用 `ClipStore.shared`。服务只发出用户提示，由 `main.swift` 接到 Toast；HTTP 服务接收注入的网页内容，不导入页面布局。

当前仍使用一个 SwiftPM executable target，避免为了目录调整引入分发变化。`python3 scripts/check_architecture.py` 检查依赖边界；以后改颜色、布局或动效应集中在 `Presentation`，不得让 `Domain`、`Application` 或 `Infrastructure` 反向依赖窗口和动画类型。`./scripts/test_tree_ui.sh` 会先执行此检查，再验证真实原生界面行为。

自定义热键：改 `HotKeyManager.register(keyCode:carbonModifiers:)` 参数（kVK_ANSI_* + cmdKey/shiftKey/optionKey/controlKey）。
