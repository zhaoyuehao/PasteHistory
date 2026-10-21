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
- 面板定位日志：`~/Library/Application Support/PasteHistory/anchor_trace.log`，每次打开面板写一行
  （结论 `below-input` / `above-input` / `below-input/shrunk-to-N` / `fallback-center` + role + 坐标）。
  真机说「没贴过去 / 有遮挡」时先看它：没拿到输入框（fallback-center）和位置算错（能贴但贴歪）是两回事。
  文件超过 200KB 会整体重写，不会无限涨。

## 维护 / 调试参数

```bash
PasteHistory.app/Contents/MacOS/PasteHistory --show            # 启动即打开面板（UI 冒烟）
PasteHistory.app/Contents/MacOS/PasteHistory --show --trace-anchor   # 额外把定位结论打到 NSLog（落盘是默认开着的，见下）
PasteHistory.app/Contents/MacOS/PasteHistory --show --fake-field 100,470,300,60   # 喂一个假输入框（AX 坐标），绕开 AX 直接验证定位几何
PasteHistory.app/Contents/MacOS/PasteHistory --show-pair       # 启动即打开手机同步配对面板（UI 冒烟）
PasteHistory.app/Contents/MacOS/PasteHistory --print-ax         # 把辅助功能授权状态写到 ax_status.txt
PasteHistory.app/Contents/MacOS/PasteHistory --paste-latest     # 对最新记录走完整粘贴流程
PasteHistory.app/Contents/MacOS/PasteHistory --smoke-panel-paste # 复现真实路径：开面板 → 选一条 → 回车粘贴（需前台有聚焦输入框）
PasteHistory.app/Contents/MacOS/PasteHistory --purge-ids a,b    # 清除指定记录（DB + iCloud + 墓碑）
PasteHistory.app/Contents/MacOS/PasteHistory --restore-images   # 从 iCloud 恢复本地缺失的原图
```

## 协作流程（硬性）

- **每次从最新的 origin/main 开始写代码**：动手前先
  `git -c credential.helper="!$HOME/Documents/PasteHistory/.git/credential-personal.sh" fetch https://github.com:443/zhaoyuehao/PasteHistory.git main`，
  把本地 main 快进/对齐到 FETCH_HEAD，再从这个最新点拉新分支。**禁止基于过期的本地 main 开发**。
- **所有改动走 PR**：开分支 → 提交 → 推分支 → `gh pr create` → review 后再合并。**禁止直接推 main**。
- **此仓库始终用个人号 `zhaoyuehao`**（仓库归属 `zhaoyuehao`，不是公司号）。
  本机全局 `insteadOf` 会把 `https://github.com/` 改写为 SSH 并走公司号 `zhaoyuehao_codeck`，
  所以仓库内已做了三层锁定，**直接 `git push` / `gh pr create` 即可，不要再手写凭据参数**：

  1. `credential.https://github.com/zhaoyuehao/PasteHistory.git.helper`：
     先写空值清空全局助手（verdent + `gh auth git-credential`），再挂 `.git/credential-personal.sh`。
  2. `url.https://github.com:443/zhaoyuehao/PasteHistory.git.insteadOf`：
     把 `https://github.com/...` 和 `git@github.com:...` 两种写法都归一到 `:443` 形式，绕开全局 SSH 改写。
  3. `gh auth switch --user zhaoyuehao`（gh 没有按仓库切账号的能力，切了会影响其它仓库；
     回公司仓库时用 `gh auth switch --user zhaoyuehao_codeck` 切回去）。

  自查凭据到底走哪个号（应恒为 `zhaoyuehao`，与公司号活跃与否无关）：

  ```bash
  printf 'protocol=https\nhost=github.com\npath=zhaoyuehao/PasteHistory.git\n' | git credential fill
  ```

  保留的手工兜底（helper 脚本失效时用）：

  ```bash
  git -c credential.helper="!$HOME/Documents/PasteHistory/.git/credential-personal.sh" \
      push https://github.com:443/zhaoyuehao/PasteHistory.git <branch>
  ```

  **`!` + 绝对路径是必须的**：写成相对路径 `.git/credential-personal.sh` 时 git 会把它当子命令，
  报 `credential-...  is not a git command` 并退化到匿名推送（会失败）。helper 内部走
  `gh auth token --user zhaoyuehao`（个人号，已登录）。
  推显式 URL 不会更新 `origin/main` 指针，`git status` 可能误报 `ahead N`——以
  `git ls-remote --heads https://github.com:443/zhaoyuehao/PasteHistory.git` 为准，
  必要时 `git update-ref refs/remotes/origin/main <sha>` 校正。
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
| `Theme.swift` | 字号 / 图标档位与语义色（`Palette.meta` / `.warning` 按 WCAG AA 反解） |
| `Motion.swift` | 动效令牌（选中 / 连按 / 边界回弹 / 悬停），View 与 ViewModel 共用 |
| `PasteService.swift` / `AXFocus.swift` | 回写剪贴板、AX 权限、捕获并还原聚焦输入框、模拟 ⌘V |
| `PasteCycler.swift` | ⇧⌘V 循环粘贴：不开面板，⌘Z 撤回上一条再贴更早一条 |
| `OCRIndexer.swift` | Vision 文字识别 + 场景分类 |
| `iCloudSync.swift` | 一记录一文件导出/导入 + 墓碑 + 对账 |
| `WebSyncServer.swift` | Network.framework 手写 HTTP 服务（局域网） |
| `WebSyncPage.swift` | 手机端单文件 HTML/JS（含纯 JS 加密回退） |
| `QRPairPanel.swift` | 配对二维码面板 |

## 修改时务必遵守

1. **任何状态切换都必须有阻尼感，没有阻尼感就不觉得流畅**（用户原话，最高优先级）。
   这条**优先于密度、优先于「一屏多显示几条」这类优化**——行内展开被删那次阻尼感跟着
   一起没了，用户当场就发现。删交互前先问一句：还有阻尼感吗？
   - 阻尼感 = **有一个东西真的在移动** × **幅度够大** × **连续可打断**，缺一个就没感觉。
   - 所以选中高亮必须是**一个会移动的物体**（`matchedGeometryEffect`），而不是每行的
     `fill` 各自淡入淡出：后者中间没有任何东西在走，人眼对交叉淡化几乎无感，
     表现出来就是「上下选中的感觉没了」。
   - 连按方向键时**把弹簧压短**（`Motion.selectionFast`），不是关掉
     （`disablesAnimations = true`）。关掉等于瞬移，而连续移动恰恰最需要阻尼。
2. **HTTP 服务不能跑 MainActor**。菜单跟踪（nested runloop）或主线程弹窗会让服务假死。
   路由/加解密全在 `queue`（`com.verdent.pastehistory.websync`）；读用独立 SQLite 连接，写 `DispatchQueue.main.async`。
3. **禁止用 `NSJSONSerialization` 序列化顶层 String**——会抛 ObjC 异常直接崩进程，用 `JSONEncoder`。
4. **Vision 识别中文必须用 `.accurate`** 并显式给 `zh-Hans`/`zh-Hant`/`en-US`；`.fast` 识别中文是乱码。
5. **不要在 SQLite 串行队列内再 `queue.sync`**（会死锁），需要总数用不 dispatch 的私有方法。
6. 手机端是**明文 HTTP 局域网地址**（非 Secure Context），页面内任何 Web API 都要考虑不可用，见 MEMORY.md。
7. 改手机端加密实现后，必须跑 node 交叉验证（方法见 MEMORY.md「加密自测」）。

## 手机端自测速查

```bash
curl -s http://127.0.0.1:8377/ | tail -1                    # 页面可达
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8377/apple-touch-icon.png
defaults read com.verdent.pastehistory webSyncPairCode      # 配对码（服务端生成并持久化）
```
