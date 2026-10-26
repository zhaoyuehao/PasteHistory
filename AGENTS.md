# AGENTS.md

PasteHistory 是 macOS 菜单栏剪贴板历史工具，采用 SwiftPM executable target 和脚本打包，没有 Xcode 工程。

## 开始工作

- [README.md](README.md)：用户行为、快捷键和数据位置。
- [开发与排障](docs/development.md)：构建、签名、测试和维护参数。
- [架构](docs/architecture.md)：模块职责及依赖方向。
- [同步](docs/sync.md)：HTTP / iCloud 协议、加密范围与自测。
- [许愿树](docs/ivory-tree/README.md)：交互、模型及验收。
- [MEMORY.md](MEMORY.md)：已定决策与回归原因。

文档中的行为和路径以最新 main 的实现为准；历史设计稿仅作参考。

## 构建与验证

```sh
./scripts/build_app.sh
open PasteHistory.app
```

日常构建必须使用 **Apple Development** 证书。脚本虽支持自签 / ad-hoc 回退，但 ad-hoc 每次重建的身份变化会影响 TCC 辅助功能授权。移动目录后遇到模块缓存路径错误，删除 `.build` 再构建。

修改结构后运行 `python3 scripts/check_architecture.py` 与 `./scripts/test_tree_ui.sh`（首次先 `mkdir -p .build`）。原生 UI 测试需图形桌面；具体改动的验证范围见开发文档。不要为了证明 prompt 文案、格式化输出中的偶然字段或简单实现细节而添加成堆的低信号断言；优先行为测试和类型 / 构建检查。

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

  只输出用户名检查凭据路由（应为 `zhaoyuehao`）；禁止直接展示 `git credential fill` 的完整输出，其中包含 token：

  ```bash
  printf 'protocol=https\nhost=github.com\npath=zhaoyuehao/PasteHistory.git\n' | git credential fill | sed -n 's/^username=/username=/p'
  ```

  仓库级凭据配置未生效时，可显式指定现有 helper 推送当前分支（helper 文件本身需可用）：

  ```bash
  git -c credential.helper="!$HOME/Documents/PasteHistory/.git/credential-personal.sh" \
      push https://github.com:443/zhaoyuehao/PasteHistory.git HEAD
  ```

  **`!` + 绝对路径是必须的**：写成相对路径 `.git/credential-personal.sh` 时 git 会把它当子命令，
  报 `credential-...  is not a git command` 并退化到匿名推送（会失败）。helper 内部走
  `gh auth token --user zhaoyuehao`（个人号，已登录）。
  推显式 URL 不会更新 `origin/main` 指针，`git status` 可能误报 `ahead N`——以
  `git ls-remote --heads https://github.com:443/zhaoyuehao/PasteHistory.git` 为准，
  必要时 `git update-ref refs/remotes/origin/main <sha>` 校正。
- 远端 main 领先时（用户在 GitHub 上合并了 PR）：`git fetch <url> main && git rebase FETCH_HEAD`，不要 force push。

## 目录与依赖边界

- `Domain/` 不依赖界面框架；`Application/` 管理业务状态和输入时序，不调用 `withAnimation` 或动画令牌。
- `Infrastructure/` 可用 AppKit 系统适配，但不创建界面窗口，不依赖 Presentation。图片读取 / 降采样 / 缓存留在 Media，数据写入经过 ClipStore / HistoryDatabase。
- `Presentation/` 负责布局和输入绑定；通用动效参数与纸面过渡留在 `Animation/`。`main.swift` 负责注入图片目录、网页和提示呈现器。
- 保持一个 executable target。SwiftPM 与独立脚本均递归发现源文件，不能恢复顶层 `*.swift` 假设。
- 改数据模型、SQLite、同步协议或剪贴板载荷必须明确说明，不能夹在视觉调整里。完整模块索引见[架构](docs/architecture.md)。

## 交互约束

1. **任何状态切换都必须有阻尼感，没有阻尼感就不觉得流畅。** 这条优先于密度和「一屏多显示几条」。阻尼感需要真实移动的物体、足够幅度、连续可打断；选中高亮使用移动的共享物体（`matchedGeometryEffect`），不能退化为每行填色交叉淡化。连按方向键压短弹簧（`Motion.selectionFast`），不能关闭动画导致瞬移；系统「减少动态效果」保留专用降级路径。
2. 图片纸签展示图片，缺图保留占位，不用 OCR 代替图片。OCR 继续参与搜索，预览中滚动阅读。
3. 树模式预览在自身窗口内接收双指缩放，无需点击；整张纸签与图文一起等比缩放，不叠加内部缩放。阅读逻辑尺寸固定，滚动可用；同次预览切换记录保留倍率，关闭后重开复位，不持久化。手势不得扩展到树体或桌面。
4. 预览保持非 key 窗口，键盘留在搜索框。只在预览期间安装应用内 local magnify monitor，严格匹配窗口与窗口内坐标，处理后消费一次，关闭 / 切列表时移除。禁止 global monitor 或重定向其他窗口手势。回归覆盖非 key、范围排除与生命周期；模拟路由不替代真实触控板验收。
5. 树体装饰窗口忽略鼠标，仅纸签、搜索签和布局控件接收输入。原生拖放只复制，不移动原文件、不改系统通用剪贴板；保留取消和目标焦点行为。

## 数据与同步约束

1. **HTTP 路由 / 加解密不能跑 MainActor**：使用 `com.verdent.pastehistory.websync` 网络队列、独立 SQLite 读连接，写入通过 `DispatchQueue.main.async`。菜单跟踪或主线程弹窗不能阻塞网络响应。
2. **禁止用 `NSJSONSerialization` 序列化顶层 String**，使用 `JSONEncoder`，避免 ObjC 异常导致进程崩溃。
3. **SQLite 串行队列内禁止再次 `queue.sync`**；需要内部查询时调用不重复 dispatch 的私有方法。
4. Vision 中文识别使用 `.accurate`，显式设置 `zh-Hans` / `zh-Hant` / `en-US`。
5. 手机默认是局域网明文 HTTP，所有 Web API 均需考虑不可用；不能把 localhost 的能力当作手机端能力。
6. 修改手机加密实现必须按[加密自测](docs/sync.md#加密自测)执行 Node 交叉验证，核对两端协议；不得将内容加密描述成 HTTPS 或本地加密存储。

## 诊断入口

定位异常先读 `~/Library/Application Support/PasteHistory/anchor_trace.log`，区分 `fallback-center`（未拿到可用输入框）和已定位后的几何错误。日志超过 200,000 字节整体重写；`preview-pinch` 只记手势阶段、倍率及窗口信息，不记正文。维护参数作用于真实数据，运行前核对[前提与副作用](docs/development.md#启动与维护参数)。
