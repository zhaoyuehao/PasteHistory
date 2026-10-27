# Tree resources and interaction

[Home](../README.md) · [Development](development.md)

The tree presents eight history cards per group and one permanent Phone Sync card. Search, previews and history operations share selection state; the phone card is a presentation-only action, never a stored record. User shortcuts are documented in the README.

## Interaction contracts

- Opening centers the whole tree on the screen under the pointer. Layout mode can move it temporarily and save a size preset; the next opening centers it again.
- Clicking a card selects and previews it. Clicking the expanded paper closes it, while text selection, scrolling, pinching and pairing buttons remain usable.
- History previews unfold from the card's hanging hole, hide the original card during expansion, avoid screen edges and return to the card on close. Their base size stays stable across history navigation; the phone preview uses a separate 340×390 reading layout.
- Pinching scales the whole paper, keeps search keyboard focus, and settles within 100%–200%, limited by available screen space. Scale survives record changes within the preview session and resets on reopening. Do not stack internal content magnification on top.
- Decorative windows ignore mouse events; small card/search/layout windows own input. Global mouse observation may close the tree but must not intercept/replay clicks or steal the destination app's focus.
- Native dragging begins after 5pt movement, fixes record identity at mouse-down and supports copy only. Reject missing file groups; export images as independent temporary copies for asynchronous receivers. Preserve cancellation behavior and source windows during dragging. Layout mode disables card actions.
- Open/close, follow and page transitions remain interruptible; use the existing Reduce Motion path. Animation parameters live in `Presentation/Animation/`, not in duplicated documentation constants.

## Model

[`ivory_tree.scn`](../Sources/PasteHistory/Resources/ivory_tree.scn) is the active SceneKit asset: a deeper tree volume and five separately staged bird groups, with depth and surface-snapped attachment points. The export keeps three restrained material roles—warm ivory tree, graphite birds, and amber beaks/feet/eyes—so depth reads without turning the tree into a multicolour illustration. AppKit renders readable paper cards over the SceneKit scene. The build script packages the SwiftPM resource bundle under `Contents/Resources`; development uses `Bundle.module`.

The editable `Ivory_Tree.blend` is **not in this repository**. The checked-in `.scn` is enough to build and run; changing the model requires the original authoring file. The current export is the `ivory-v2` pass: a slightly broader trunk and explicit front/back staging for the five bird controllers. Blender is not a runtime dependency.

## Export

Open the authoring file in Blender. Tree objects start with `白枝 ·`; the five bird pose Empty objects start with `Bird `. Run the following in Blender's Python environment, replacing `/absolute/repo`:

```python
export_path = '/absolute/repo/.build/ivory-export/parts'
exec(compile(open('/absolute/repo/scripts/export_ivory_tree.py').read(), 'export_ivory_tree.py', 'exec'))
```

Then, from the repository root:

```sh
swift scripts/convert_ivory_tree.swift .build/ivory-export/parts Sources/PasteHistory/Resources/ivory_tree.scn
```

The exporter uses temporary meshes, adds branch depth, shifts birds with their perches, splits bird accents for material separation, and reduces mesh density without modifying the authoring scene. After changing depth or branch positions, check `IvoryTreeSceneView.anchor` search seeds and surface snapping.

## Geometry check

On a logged-in macOS desktop, from the repository root:

```sh
mkdir -p .build
swiftc -swift-version 5 Sources/PasteHistory/Presentation/Tree/IvoryTreeScene.swift \
  Sources/PasteHistory/Presentation/Tree/IvoryTreePaperView.swift \
  Sources/PasteHistory/Presentation/Windows/HistoryPanel.swift \
  Sources/PasteHistory/Presentation/Tree/TreeInteraction.swift \
  Sources/PasteHistory/Presentation/Style/IvoryPaperStyle.swift \
  Sources/PasteHistory/Presentation/Animation/TreeMotion.swift \
  Sources/PasteHistory/Presentation/Animation/Motion.swift \
  Sources/PasteHistory/Presentation/Animation/MotionClock.swift \
  Sources/PasteHistory/Presentation/Animation/SettlingTrack.swift \
  Sources/PasteHistory/Presentation/Animation/PaperPreviewFlight.swift \
  Sources/PasteHistory/Shared/Localization.swift \
  scripts/test_ivory_tree.swift \
  -o .build/tree-smoke -framework AppKit -framework SceneKit
.build/tree-smoke Sources/PasteHistory/Resources/ivory_tree.scn .build/ivory-preview
```

This uses production rendering and synthetic records, without user history or clipboard access. Inspect generated `front.png` and `angle.png` in `.build/ivory-preview/`; keep them as local build output rather than checked-in screenshots.

After model changes, run `./scripts/test_tree_ui.sh` and `./scripts/build_app.sh` to verify live views and resource packaging. UI coverage includes search/OCR, history actions, the permanent phone card, input boundaries, preview motion/scale and cleanup. Use the [interactive drag and device checks](development.md#validation) for behavior synthetic events cannot establish.
