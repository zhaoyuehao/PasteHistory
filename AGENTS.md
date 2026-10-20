# AGENTS.md

PasteHistory：macOS 菜单栏剪贴板历史（SwiftPM 可执行 target + 手工打包 .app，无 Xcode 工程文件）。

## 构建与运行

```bash
cd ~/Documents/PasteHistory
./scripts/build_app.sh          # swift build -c release → 打包 PasteHistory.app → 自动签名
open PasteHistory.app           # 运行（菜单栏出现剪贴板图标）
```

- 签名由脚本自动探测身份：**Apple Development > 自签 PasteHistory > ad-hoc**。
  **必须用 Apple Development 证书**：ad-hoc 每次重建 cdhash 变化，TCC 会判定辅助功能权限失效并反复弹窗。
- 移动项目目录后必须 `rm -rf .build` 重新构建：模块缓存里写死了旧绝对路径，会报
  `PCH was compiled with module cache path ... but the path is currently ...`。
- 数据目录：`~/Library/Application Support/PasteHistory/`（history.sqlite + images/），iCloud 同步走 iCloud Drive 的 `PasteHistory/`。

## 维护 / 调试参数

```bash
PasteHistory.app/Contents/MacOS/PasteHistory --show            # 启动即打开面板（UI 冒烟）
PasteHistory.app/Contents/MacOS/PasteHistory --print-ax         # 把辅助功能授权状态写到 ax_status.txt
PasteHistory.app/Contents/MacOS/PasteHistory --paste-latest     # 对最新记录走完整粘贴流程
PasteHistory.app/Contents/MacOS/PasteHistory --purge-ids a,b    # 清除指定记录（DB + iCloud + 墓碑）
PasteHistory.app/Contents/MacOS/PasteHistory --restore-images   # 从 iCloud 恢复本地缺失的原图
```

## 协作流程（硬性）

- **所有改动走 PR**：开分支 → 提交 → 推分支 → `gh pr create` → review 后再合并。**禁止直接推 main**。
- 推送用个人号凭据（本机全局 `insteadOf` 会把 `https://github.com/` 改写为 SSH 并走公司号）：

  ```bash
  git -c credential.helper=.git/credential-personal.sh \
      push https://github.com:443/zhaoyuehao/PasteHistory.git <branch>
  ```

  输出里的 `credential-...  is not a git command` 是无害警告。
  推显式 URL 不会更新 `origin/main` 指针，`git status` 可能误报 `ahead N`——以
  `git ls-remote --heads https://github.com:443/zhaoyuehao/PasteHistory.git` 为准。
- 远端 main 领先时（用户在 GitHub 上合并了 PR）：`git fetch <url> main && git rebase FETCH_HEAD`，不要 force push。

## 模块职责

| 文件 | 职责 |
|---|---|
| `main.swift` | AppDelegate、菜单栏、iCloud/WebSync 启动、维护参数 |
| `ClipboardMonitor.swift` | NSPasteboard changeCount 轮询，接力/保密类型识别 |
| `HistoryDatabase.swift` | SQLite3 C API（WAL、分页、串行队列） |
| `ClipStore.swift` | 分页门面、Settings（UserDefaults） |
| `PanelController.swift` | ⇧⌘C 面板（NSHostingController 承载 SwiftUI） |
| `HistoryView.swift` | 面板 UI（搜索 / 列表 / 键盘导航） |
| `PasteService.swift` / `AXFocus.swift` | 回写剪贴板、AX 权限、捕获并还原聚焦输入框、模拟 ⌘V |
| `OCRIndexer.swift` | Vision 文字识别 + 场景分类 |
| `iCloudSync.swift` | 一记录一文件导出/导入 + 墓碑 + 对账 |
| `WebSyncServer.swift` | Network.framework 手写 HTTP 服务（局域网） |
| `WebSyncPage.swift` | 手机端单文件 HTML/JS（含纯 JS 加密回退） |
| `QRPairPanel.swift` | 配对二维码面板 |

## 修改时务必遵守

1. **HTTP 服务不能跑 MainActor**。菜单跟踪（nested runloop）或主线程弹窗会让服务假死。
   路由/加解密全在 `queue`（`com.verdent.pastehistory.websync`）；读用独立 SQLite 连接，写 `DispatchQueue.main.async`。
2. **禁止用 `NSJSONSerialization` 序列化顶层 String**——会抛 ObjC 异常直接崩进程，用 `JSONEncoder`。
3. **Vision 识别中文必须用 `.accurate`** 并显式给 `zh-Hans`/`zh-Hant`/`en-US`；`.fast` 识别中文是乱码。
4. **不要在 SQLite 串行队列内再 `queue.sync`**（会死锁），需要总数用不 dispatch 的私有方法。
5. 手机端是**明文 HTTP 局域网地址**（非 Secure Context），页面内任何 Web API 都要考虑不可用，见 MEMORY.md。
6. 改手机端加密实现后，必须跑 node 交叉验证（方法见 MEMORY.md「加密自测」）。

## 手机端自测速查

```bash
curl -s http://127.0.0.1:8377/ | tail -1                    # 页面可达
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8377/apple-touch-icon.png
defaults read com.verdent.pastehistory webSyncPairCode      # 配对码（服务端生成并持久化）
```
