# 开发与排障

[文档索引](README.md) · [架构](architecture.md) · [同步](sync.md)

所有命令默认从仓库根目录执行。开始修改前遵守 [AGENTS.md](../AGENTS.md) 的最新 main、个人账号和 PR 流程。

## 构建和签名

要求 macOS 14+、Swift 6 工具链；包当前使用 Swift 5 语言模式。测试脚本另需 Python 3；模型导出需 Blender，加密交叉验证需 Node.js。正常构建和运行不依赖 Blender。

```sh
swift --version
./scripts/build_app.sh
codesign -dv --verbose=4 PasteHistory.app
open PasteHistory.app
```

`build_app.sh` 执行 release 构建，将二进制、Info.plist 和 `PasteHistory_PasteHistory.bundle` 装入 `.app`，再按 Apple Development、自签 PasteHistory、ad-hoc 的顺序选择签名。**脚本允许回退，不代表回退签名满足项目的日常使用要求**：应使用 Apple Development，并检查构建输出和 `codesign` 的 Authority。

辅助功能授权与签名身份相关。重建后反复要求授权时，先确认签名，再到系统设置删除多余的 PasteHistory 条目并为当前应用重新授权。

移动仓库后如遇 `PCH was compiled with module cache path ...`，在仓库根目录删除旧构建缓存后重建：

```sh
rm -rf .build
./scripts/build_app.sh
```

## 按改动选择验证

| 改动 | 验证 |
| --- | --- |
| 文档 | 链接 / 路径 / 参数与当前实现核对，`git diff --check`；无需启动应用 |
| 目录、依赖边界 | `python3 scripts/check_architecture.py`，再运行 UI 冒烟 |
| 原生界面、预览、输入、动效 | `./scripts/test_tree_ui.sh`，必要时 `--interactive` 人工观察 |
| 纸签跨应用拖放 | `./scripts/test_drag_ui.sh`；图片加 `--drag-image`，文件加 `--drag-files` |
| 树模型 | [许愿树几何冒烟与资源验证](ivory-tree/README.md#验证) |
| 手机网页加密 | [Node.js 交叉验证及端到端检查](sync.md#加密自测) |
| 打包或资源 | `./scripts/build_app.sh`，检查签名并启动验证 |

原生 UI 测试需要已登录的 macOS 图形桌面。第一次执行前准备构建目录：

```sh
mkdir -p .build
./scripts/test_tree_ui.sh
```

UI 脚本使用临时 SQLite 和合成数据，不读取用户历史或写入系统通用剪贴板；它会创建测试窗口和构建日志。构建 / 编译日志位于 `.build/tree-ui-build.log` 与 `.build/tree-ui-compile.log`。交互模式会保留演示窗口。

自动测试覆盖路由、状态和部分动画几何。真实外部应用的粘贴、跨进程拖放与物理触控板手势仍需人工验证；模拟事件通过不能代替实机验收。不要为文案或偶然字段堆叠低信号断言。

## 启动与维护参数

以下参数仅在**新进程启动**时解析。先从菜单栏退出已运行的 PasteHistory，再启动一次待测应用；重复 `open` 现有进程只会打开面板，不重放维护参数。直接运行可执行文件时也不要同时留下另一实例。

```sh
PasteHistory.app/Contents/MacOS/PasteHistory --show
```

这些命令使用真实数据目录。粘贴参数会向当前目标应用发送按键，删除参数会修改历史。

| 参数 | 行为与前提 |
| --- | --- |
| `--show` | 启动即打开许愿树 |
| `--show --trace-anchor` | 打开面板，并将默认落盘的定位日志同时写到 NSLog |
| `--show-pair` | 打开手机配对面板 |
| `--print-ax` | 写出辅助功能状态；未授权会请求权限 |
| `--paste-latest` | 将最近记录走完整粘贴流程；需预先聚焦测试输入框 |
| `--smoke-panel-paste` | 打开面板后走选中并粘贴路径；需预先聚焦测试输入框 |
| `--smoke-preview` | 打开预览、移动选择、关闭预览，日志输出 open / switch-follow / close；至少需要两条历史 |
| `--purge-ids "uuid1,uuid2"` | 删除指定真实记录，并在 iCloud 同步处于活动状态时删除远端记录文件、写墓碑；使用有效 UUID |
| `--restore-images` | 从活动的 iCloud 同步目录恢复本地缺失原图 |

当前只保留许愿树，没有视图切换参数；旧列表尺寸和输入框定位参数已移除。维护命令执行后应用仍常驻；不要把启动成功等同于维护已成功完成，应检查日志和数据结果。

## 日志与常见问题

数据目录为 `~/Library/Application Support/PasteHistory/`。

| 症状 | 先检查 |
| --- | --- |
| 回车只复制、不自动粘贴 | 辅助功能授权、签名身份和菜单中的自动粘贴开关 |
| 预览双指缩放无反应 | 指针是否在预览内；查看 `preview-pinch` 行，并用真实触控板复现 |
| 手机连不上 / 配对失效 | [手机同步排障](sync.md#连接排障) |
| 图片原图缺失 | 先确认 iCloud 文件已经到达，再使用 `--restore-images` |
| 面板关闭后立刻重开又消失 | 检查窗口代际号与延迟焦点恢复，参见 [维护记忆](../MEMORY.md) |

`anchor_trace.log` 默认写入，超过 200,000 字节后整体重写。旧版本的列表定位日志已停用，树的位置由布局设置决定。`preview-pinch` 记录手势阶段、倍率与窗口信息，不记录剪贴板正文。

`--print-ax` 写出同目录下的 `ax_status.txt`，内容为 `trusted` 或 `not-trusted`。

## 备份与恢复边界

需要保留历史时，先退出应用，再备份整个 `~/Library/Application Support/PasteHistory/`，同时保留 `history.sqlite`、存在的 `-wal` / `-shm` 文件和 `images/`。不要只复制正在写入的单个 SQLite 主文件。

iCloud 是同步副本，删除会传播，不能替代独立备份。恢复旧数据库前先处理好同步开关与远端墓碑；`--restore-images` 只补图片，不恢复已删除的记录，也不撤销墓碑。
