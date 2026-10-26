# 架构

[文档索引](README.md) · [开发与排障](development.md) · [协作规则](../AGENTS.md)

PasteHistory 使用一个 SwiftPM executable target。目录分层约束依赖关系，不引入额外构建或分发目标。SwiftPM 递归发现源文件，独立测试脚本也必须递归收集。

## 目录职责

以下路径相对于 [`Sources/PasteHistory/`](../Sources/PasteHistory/)。

| 层 / 目录 | 主要入口与职责 |
| --- | --- |
| `main.swift` | 组合入口、菜单栏、全局热键、服务生命周期、启动参数；注入网页和提示呈现器 |
| `Domain/` | `Models.swift`：记录、内容指纹与检索字段；不依赖界面框架 |
| `Application/` | `ClipStore` 管理记录和分页；`Settings` 管理偏好；`HistoryViewModel` 管理选择和操作；`HistoryKeyboardState` 管理输入规则 |
| `Infrastructure/Persistence/` | `HistoryDatabase`：SQLite3 C API、WAL、查询、去重与迁移 |
| `Infrastructure/Clipboard/` | 捕获剪贴板、全局热键、AX 焦点恢复、粘贴与循环粘贴、原生拖放载荷 |
| `Infrastructure/Media/` | Vision OCR、文件元数据、预览图片读取 / 降采样 / 缓存 |
| `Infrastructure/Sync/` | iCloud 文件同步与局域网 HTTP 服务 |
| `Infrastructure/Diagnostics/` | `AnchorTrace`：定位与预览手势日志 |
| `Presentation/History/` | 搜索与列表、树 / 列表切换、临时布局状态 |
| `Presentation/Tree/` | SceneKit 树体、纸签、挂点和受限交互窗口 |
| `Presentation/Windows/` | 窗口生命周期、定位、焦点和键盘路由 |
| `Presentation/Preview/` | 预览窗口、内容、整张纸面缩放与滚动 |
| `Presentation/Animation/` | 阻尼令牌、树进场、翻页、预览开合 / 跟随 / 缩放回弹 |
| `Presentation/Style/`、`Shared/` | 字体、间距、颜色、纸面样式、摘要和提示条 |
| `Presentation/Sync/` | 手机网页和二维码配对面板 |
| `Shared/Localization.swift` | 各层共用的简体中文、繁体中文与英文文案；手机网页在自身模块内处理语言 |
| `Resources/ivory_tree.scn` | 随应用打包的 SceneKit 模型 |

## 数据与输入流

```text
系统剪贴板 → ClipboardMonitor → ClipStore → HistoryDatabase / 图片目录
                                    ├→ OCRIndexer → 更新搜索索引
                                    └→ iCloudSync → iCloud 文件

键盘 / 纸签操作 → PanelController / HistoryView → HistoryViewModel → ClipStore
                                                    └→ PasteService → 恢复原焦点 → ⌘V

手机网页 ↔ WebSyncServer（独立网络队列）→ 独立 SQLite 读连接
                         └→ 解密后异步派发主队列 → ClipStore
```

- 监视器每 0.4 秒检查 `NSPasteboard.changeCount`，按类型和忽略规则捕获；自写剪贴板会同步计数，避免重复入库。轮询不是完整的系统复制事件日志。
- `ClipStore` 每批加载 60 条，搜索防抖 250ms 后执行 SQL。树视图在结果序列上每组展示 8 条，列表与树共用搜索、排序和选中项。
- 图片原图存文件，数据库保存文件名与缩略图。`PreviewMediaLoader` 接收注入的图片目录，负责读取、降采样和缓存；视图不自行读取文件，也不引用 `ClipStore.shared` 获取预览资源。
- 数据服务发出 `UserFeedback`，由入口接到 Toast；HTTP 服务接收注入的网页内容，不依赖页面实现。
- iCloud 与手机 HTTP 是两条独立同步路径，手机配对密钥不会用于本地数据库或 iCloud 文件，详见[同步协议](sync.md)。

## 依赖边界

`Domain` 不导入 AppKit / SwiftUI / SceneKit。`Application` 发布业务状态与输入时序，不调用 `withAnimation` 或动画令牌。`Infrastructure` 可使用 NSImage / NSPasteboard 等系统适配，但不得创建界面窗口或依赖 Presentation 类型。

布局与动效属于 `Presentation`。表现层根据输入时序选择弹簧参数，不把动画逻辑放回 ViewModel。颜色和尺寸集中在 `Style`，通用动效集中在 `Animation`。界面层不直接执行 SQLite、文件读取或图片解码。

运行以下命令检查边界：

```sh
python3 scripts/check_architecture.py
```

更改结构还需执行 `./scripts/test_tree_ui.sh`。检查脚本是静态边界守卫，不能替代实际行为测试；数据模型、同步协议和剪贴板载荷变更需单独说明，不能混在视觉调整里。
