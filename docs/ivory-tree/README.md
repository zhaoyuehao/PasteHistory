# 3D 许愿树

默认按 `⇧⌘C` 唤起透明、无边框的桌面许愿树。树体和树下的搜索框直接浮在桌面上，没有灰色背景、大标题、说明文字或底部工具栏。`⌘L` 切回列表，记住上次选择。列表与树共用排序、搜索结果和选中记录。

- 拖动树体旋转；树的右键菜单可恢复初始视角。
- 每组显示 6 张枝头卡片。点击选中、双击粘贴；搜索框旁的箭头翻组，省略号菜单保留预览、复制、粘贴、置顶和删除。输入即筛选记录。
- `↑` / `↓`、回车、`⌘C`、`⌘1–9`、空格 / `⌘Y` 沿用面板的快捷键；接近加载边界时继续读取历史记录。
- SceneKit 渲染实际网格，包含连续树体、5 只鸟、立体卡片、透视相机、侧光及自阴影。无网络模型服务和运行时 Blender 依赖。
- 旋转与选中框使用可打断的阻尼运动；系统减少动态效果时，选中框使用短淡入。静止后停止动画计时器，离开树视图时释放渲染器。

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

导出器按连续函数增加枝条前后错落，鸟按栖息位置整体平移，再降低网格密度。若更改此函数或主枝位置，需要同步 `IvoryTreeSceneView.anchor` 的挂点。

## 验证

在已登录图形桌面的 macOS 上执行：

```sh
swiftc Sources/PasteHistory/IvoryTreeScene.swift scripts/test_ivory_tree.swift \
  -o .build/tree-smoke -framework AppKit -framework SceneKit
.build/tree-smoke Sources/PasteHistory/Resources/ivory_tree.scn .build/ivory-preview
./scripts/test_tree_ui.sh
./scripts/build_app.sh
```

几何冒烟验证五只鸟、实际纵深、透视投影、卡片命中、拖动视差、阻尼复位及空结果；UI 冒烟使用真实视图、ViewModel 和临时 SQLite 数据库，验证切换、共用选中项、复制/粘贴回调、跨组选择、分页加载、空搜索、实际搜索筛选、无边框窗口的键盘焦点、窗口和视图透明度及紧凑布局。不会读取用户历史或写入系统剪贴板。`./scripts/test_tree_ui.sh --interactive` 留下独立演示窗口。

系统输入框的最终回写沿用现有 PasteService；上述冒烟只验证回调路由，不模拟向其他应用粘贴。
