# PasteHistory 桌面体验站

纯前端 macOS 模拟桌面。Vite + TypeScript + Three.js；真实树网格来自原生 `ivory_tree.scn`，交互以仅保留许愿树的 #30 为准。没有业务后端，不读取系统剪贴板，不把演示内容持久化或上传。

```sh
cd website
npm ci
npm run dev                 # http://127.0.0.1:5173/PasteHistory/
npm test
npm run snapshot            # 更新公开 GitHub 数据的离线快照
npm run build
```

GitHub Pages 使用 `.github/workflows/website.yml`：PR 检查，main 更新和 Release 发布后构建与部署，也支持手动触发。仓库 Pages 的 Source 应设为 GitHub Actions。部署根路径为 `/PasteHistory/`。

## 体验边界

- 素材窗口模拟复制；纸签的「复制到系统」才主动调用浏览器剪贴板权限。图片的系统复制目前复制标题；演示备忘录粘贴与拖入支持图片。
- 文字、图片 OCR 文本及文件路径都是示例。文件操作只粘贴路径；浏览器端没有实现 Vision、iCloud 或手机配对服务。
- ⇧⌘V 只在页面获得键盘输入且浏览器未占用时生效。保留浏览器快捷键，按钮始终可用。中文组词与文本编辑不触发卡片删除。
- 演示记录与备忘录保存在内存中，刷新或 Dock 重置会恢复样例。localStorage 仅缓存公开 GitHub 统计 30 分钟。
- 统计遍历所有公开 Releases（包含预览版），只累计 `PasteHistory*.zip/.dmg/.pkg` 附件，排除校验文件。下载按钮选择最新带 arm64 安装包的发布版本。请求失败使用已验证缓存或构建快照；无可用数据时显示不可用。

## 模型更新

在 macOS 仓库根目录运行：

```sh
swift website/scripts/export-tree.swift Sources/PasteHistory/Resources/ivory_tree.scn website/public
```

导出 GLB 与透明 PNG。保留原树体与五只鸟的实际网格；挂点在浏览器中吸附树表面。转换工具仅开发时需要，Linux CI 直接使用已提交资源。`?fallback=1` 可验证无 WebGL 的演示；浏览器设置「减少动态效果」时移除位移动画，保留短透明度反馈。

## 预览版发布

原生代码需先经过 PR review 并合入 main，发布提交必须包含 #30。仅在 Apple Silicon Mac、存在 Apple Development 签名身份时执行：

```sh
./scripts/package_preview.sh 1.0.0-beta.1
```

脚本拒绝 ad-hoc 回退，验证 arm64、模型资源、签名和 ZIP 解压后的签名，输出到 `dist/release/1.0.0-beta.1/`。发布 GitHub prerelease `v1.0.0-beta.1` 时上传 ZIP 和 `SHA256SUMS.txt`，记录构建提交、macOS 14+、Apple Silicon，以及未经公证和 Gatekeeper 可能拦截的限制。安装包不是 Developer ID 正式分发版本。

发布前验证实际启动和隔离数据下的粘贴；不要把真实剪贴板数据库用于自动化回归。发布后手动触发网站工作流可兜底更新快照（使用自动化令牌发布时，GitHub 可能不触发下游事件）。
