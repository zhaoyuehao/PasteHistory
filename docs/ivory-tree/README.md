# 3D 许愿树

默认按 `⇧⌘V` 唤起透明、无边框的桌面许愿树。树体和树根的搜索悬签直接浮在桌面上，没有灰色背景、大标题、说明文字或底部工具栏。仅保留许愿树视图，旧版列表偏好不再生效。

- 树的视角固定，日常模式不可移动或缩放。菜单栏“调整树布局…”或 ⇧⌘M 进入独立模式，只有专用把手能移动树；小／标准／大三档尺寸，⌘R 复位，完成或 Esc 退出。每次重新唤起都恢复日常模式。
- 图片纸签优先展示完整缩略图，展开首屏仍只显示图片，向下滚动再阅读 13pt OCR 文字。图片和纯文字预览支持原生双指缩放（50%–400%）；缩放只作用于当前预览内容，切换记录或重新打开时回到初始视口。无图时保留图片占位。
- 每页显示 8 张枝头纸签。直接输入搜索，↑↓ 选记录，空格预览，回车粘贴。Page Up / Page Down（fn↑ / fn↓）翻组，⌘C 复制、⌘P 置顶、Delete 删除。搜索输入和页数收在树根悬签中，无横向搜索条、工具按钮或操作菜单。
- 树模式下，输入搜索词后直接按空格即可预览；Shift＋空格在搜索词里输入空格。中文输入法组词时，空格、方向键和回车交给输入法。⌘Y 随时预览。
- `↑` / `↓`、回车、`⌘C`、`⌘1–9`、空格 / `⌘Y` 沿用面板的快捷键；接近加载边界时继续读取历史记录。
- SceneKit 渲染实际网格，包含连续树体、5 只鸟、透视相机、侧光及自阴影；纸签以 AppKit 绘制为朝向读者的可读平面，细绳连接从真实树体网格吸附的挂点。无网络模型服务和运行时 Blender 依赖。
- 普通纸签展示两行摘要和来源；选中后展开正文、时间，图片记录显示缩略图。正文固定 13pt、辅助信息 11pt，不随树的尺寸改变。
- 树模式预览以所选纸签的挂孔为锚点就地展开（220ms），带约 1% 的轻微回弹；关闭时收回当前纸签（170ms）。纸色、4pt 圆角、细边框、挂孔和元信息与枝头纸签共用样式，展开期间隐藏原纸签，避免重影。内容随同一纸面连续放大，在途中完成源纸签到预览的交接，结束时不再叠加整窗淡入；树模式切换记录只移动纸面，不再同时滑动内部正文。只有靠近屏幕边缘时才作位置避让。
- 每次打开根据内容选择 340×210、400×247 或 480×297 的黄金矩形（约 1.618∶1）；这一轮方向键切换保持尺寸，140ms 跟随新的挂点，避免长文本反复换行排版。正文 15pt、元信息 11pt，间距采用 8／13／21pt。开合可打断，移动轻量快照，正文保持最终布局；减少动态效果时仅渐隐渐现。
- 唤起时约 220ms 从根部向上显现，翻页约 280ms 沿纸签挂点翻转。键盘立即操作当前结果，快速翻页从当前可见状态接续，不排队；鼠标在旧纸签退场后命中新页，避免误点。
- 纸签展开与移动选中框均可打断；系统减少动态效果时使用短淡入淡出。静止后停止动画计时器，离开树视图时释放渲染器。

## 输入边界

- 展示树体的大窗口始终 `ignoresMouseEvents = true`。每张纸签、搜索签和调整模式的控制条分别使用受限尺寸的子窗口；树干、枝条、小鸟和绳子不参与鼠标命中。纸签窗口包含其轻微倾斜与边缘的少量留白。
- 点击后方 App 的原始事件交由系统派发。全局鼠标监视器只观察后收起树，不拦截、不回放点击；外部切换导致的关闭不激活先前 App。
- 单击选中并预览；纸签超过 5pt 的拖动进入原生 NSDraggingSession。按下时固定记录身份，阈值后读取文字、PNG/图片文件地址或多文件 URL，只允许 copy。拖动不改变树的位置、不写系统剪贴板、不模拟粘贴；缺失文件整组拒绝。图片导出独立临时副本，接收方异步读取不受历史删除影响，七天前的导出副本后台清理。
- 原生拖放期间保留来源窗口并暂停树的外部失焦关闭，Esc 交给系统取消；成功投放后关闭树且不抢目标焦点，取消后若仍在本应用则保持树与搜索。调整布局模式禁用纸签拖放。
- 翻页中的可见纸签仍消费点击，但暂不执行操作；布局模式的纸签也不执行操作，避免误点背后的应用。收起立即撤走所有交互窗口，剩余淡出只展示画面。

## 预览

| 正面附近 | 斜侧面 |
| --- | --- |
| ![正面](front.png) | ![斜侧面](angle.png) |

预览中的记录均为虚拟数据。原模型基于用户提供的无叶白树参考图制作，应用版增加枝条纵深。模型坐标范围约为 6.41 × 8.81 × 2.66；资源内保留 Tree、Bird_01…Bird_05 六个独立组。

## 资源维护

`Sources/PasteHistory/Resources/ivory_tree.scn` 是可随应用独立分发的原生 SceneKit 资源，约 7.4 MB。打包脚本将 SwiftPM 资源包复制到 `Contents/Resources`；应用按此路径加载，开发运行使用 `Bundle.module`。

从制作阶段的可编辑 `Ivory_Tree.blend` 更新模型：

1. 在 Blender 中打开源文件。树体名以 `白枝 ·` 开头，5 个鸟的姿态控制 Empty 名以 `Bird ` 开头。
2. 通过 Blender MCP 执行以下代码（路径替换为当前仓库的绝对路径）。导出使用临时网格，不修改原场景。

   ```python
   export_path = '/absolute/repo/.build/ivory-export/parts'
   exec(compile(open('/absolute/repo/scripts/export_ivory_tree.py').read(), 'export_ivory_tree.py', 'exec'))
   ```

3. 转为应用资源：

   ```sh
   swift scripts/convert_ivory_tree.swift .build/ivory-export/parts Sources/PasteHistory/Resources/ivory_tree.scn
   ```

导出器按连续函数增加枝条前后错落，鸟按栖息位置整体平移，再降低网格密度。若更改此函数或主枝位置，可调整 `IvoryTreeSceneView.anchor` 的搜索种子；载入时会自动吸附到树体表面顶点。

## 验证

在已登录图形桌面的 macOS 上执行：

```sh
swiftc Sources/PasteHistory/Presentation/Tree/IvoryTreeScene.swift Sources/PasteHistory/Presentation/Tree/IvoryTreePaperView.swift Sources/PasteHistory/Presentation/Windows/HistoryPanel.swift Sources/PasteHistory/Presentation/Tree/TreeInteraction.swift Sources/PasteHistory/Presentation/Style/IvoryPaperStyle.swift Sources/PasteHistory/Presentation/Animation/TreeMotion.swift scripts/test_ivory_tree.swift \
  -o .build/tree-smoke -framework AppKit -framework SceneKit
.build/tree-smoke Sources/PasteHistory/Resources/ivory_tree.scn .build/ivory-preview
./scripts/test_tree_ui.sh
./scripts/build_app.sh
```

几何冒烟验证五只鸟、实际纵深、生长前后实际像素差异、纸签命中、装饰树忽略普通及 Option 拖动、连续翻页中断及空结果；UI 冒烟使用真实视图、ViewModel 和临时 SQLite 数据库，验证切换、共用选中项、复制/粘贴回调、置顶/取消置顶、删除、图片缩略图、跨组选择、分页加载、空搜索、实际搜索筛选、无边框窗口的键盘焦点、窗口和视图透明度及紧凑布局、受限输入窗口、布局模式的独立拖动与尺寸档位、关闭后无残留窗口；还验证真实 PanelController 中的筛选后鼠标命中、空格预览、方向键切换、Esc 收起和十万字文本连续切换。另验证隔离拖放剪贴板中的多行文字、PNG/导出 URL、多文件、缺失文件拒绝，以及挂孔定位、同款纸色、黄金比例及小屏等比缩放、实际窗口轻微回弹与落定、长文本导航尺寸稳定、从纸签出发的中间帧和快速开合后无残留过渡窗口。同时验证 OCR 搜索仍命中图片、图片占据纸签主体像素、展开后 OCR 可选择，以及预览服务读取注入的测试目录。不会读取用户历史或写入系统剪贴板。`./scripts/test_tree_ui.sh --interactive` 留下独立演示窗口。

系统输入框的最终回写沿用现有 PasteService；上述冒烟只验证回调路由，不模拟向其他应用粘贴。

原生跨进程拖放的人工验收：`./scripts/test_drag_ui.sh` 启动独立接收 App 和仅含合成数据的拖放来源。将聚焦的测试纸签拖入灰色接收区，应显示 `PASS TEXT`；用 `--drag-image` / `--drag-files` 分别检查 PNG 与多文件。接收器会验证内容及 copy-only 操作，不修改系统剪贴板。自动化工具难以定位非激活子窗口时，测试窗口使用同一个生产 `TreePaperSurface` 和控制器回调，但额外允许键盘聚焦。
