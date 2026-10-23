# 3D 许愿树

默认按 `⇧⌘C` 唤起透明、无边框的桌面许愿树。树体和树根的搜索悬签直接浮在桌面上，没有灰色背景、大标题、说明文字或底部工具栏。`⌘L` 切回列表，记住上次选择。列表与树共用排序、搜索结果和选中记录。

- 普通拖动树体或纸签可移动整棵树，位置会保存；按住 Option 拖动才旋转，可连续转过 360°。4pt 内的轻微抖动仍算点击。⌘R 恢复初始视角与桌面位置。
- 每页显示 8 张枝头纸签。直接输入搜索，↑↓ 选记录，空格预览，回车粘贴。Page Up / Page Down（fn↑ / fn↓）翻组，⌘C 复制、⌘P 置顶、⌘⌫ 删除。搜索输入和页数收在树根悬签中，无横向搜索条、工具按钮或操作菜单。
- 树模式下，输入搜索词后直接按空格即可预览；Shift＋空格在搜索词里输入空格。中文输入法组词时，空格、方向键和回车交给输入法。⌘Y 随时预览。
- `↑` / `↓`、回车、`⌘C`、`⌘1–9`、空格 / `⌘Y` 沿用面板的快捷键；接近加载边界时继续读取历史记录。
- SceneKit 渲染实际网格，包含连续树体、5 只鸟、透视相机、侧光及自阴影；纸签以 AppKit 绘制为朝向读者的可读平面，细绳连接从真实树体网格吸附的挂点。无网络模型服务和运行时 Blender 依赖。
- 普通纸签展示两行摘要和来源；选中后展开正文、时间，图片记录显示缩略图。正文固定 13pt、辅助信息 11pt，不随旋转缩小。
- 树模式预览优先靠树侧边落位，窄屏夹回屏幕内；原生 NSTextView 按需排版长文本，连续切换不保留旧内容过渡层。
- 唤起时约 220ms 从根部向上显现，翻页约 280ms 沿纸签挂点翻转。键盘立即操作当前结果，快速翻页从当前可见状态接续，不排队；鼠标在旧纸签退场后命中新页，避免误点。
- 旋转、纸签展开与移动选中框均可打断；系统减少动态效果时使用短淡入淡出。静止后停止动画计时器，离开树视图时释放渲染器。

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
swiftc Sources/PasteHistory/IvoryTreeScene.swift Sources/PasteHistory/IvoryTreePaperView.swift scripts/test_ivory_tree.swift \
  -o .build/tree-smoke -framework AppKit -framework SceneKit
.build/tree-smoke Sources/PasteHistory/Resources/ivory_tree.scn .build/ivory-preview
./scripts/test_tree_ui.sh
./scripts/build_app.sh
```

几何冒烟验证五只鸟、实际纵深、生长前后实际像素差异、纸签命中、超过 360° 的旋转及挂签视差、普通拖动与 Option 旋转区分、阻尼复位、连续翻页中断及空结果；UI 冒烟使用真实视图、ViewModel 和临时 SQLite 数据库，验证切换、共用选中项、复制/粘贴回调、置顶/取消置顶、删除、图片缩略图、跨组选择、分页加载、空搜索、实际搜索筛选、无边框窗口的键盘焦点、窗口和视图透明度及紧凑布局；还验证真实 PanelController 中的筛选后鼠标命中、空格预览、方向键切换、Esc 收起和十万字文本连续切换。不会读取用户历史或写入系统剪贴板。`./scripts/test_tree_ui.sh --interactive` 留下独立演示窗口。

系统输入框的最终回写沿用现有 PasteService；上述冒烟只验证回调路由，不模拟向其他应用粘贴。
