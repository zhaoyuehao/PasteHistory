# PasteHistory desktop demo

A static Vite + TypeScript + Three.js website, served at `/PasteHistory/`. The sculpture is rendered by SceneKit from the native `ivory_tree.scn`, with the camera, material, lighting, five birds and surface-snapped attachment points from native main `0765399`. Three.js projects the exported world-space anchors; accessible DOM papers remain interactive. There is no application backend, clipboard polling, or persistent demo history.

```sh
cd website
npm ci
npm run dev                 # http://127.0.0.1:5173/PasteHistory/
npm test
npm run snapshot            # Refresh public GitHub statistics
npm run build
```

## Experience

The first visit opens the native default tree layout with eight history records, a permanent Phone Sync card and the root search tag. The same frame and point sizes remain in use when selecting, searching and previewing: there is no separate three-record hero, whole-tree zoom or layout transition. The download button is centered below the root search tag, followed by a quiet GitHub link and statistics. Copy Samples and Notes stay visible on either side of the tree. The shortcut guide and drag hint live inside Notes. The bottom toolbar is removed; Actions, Reset and the language selector are in the top menu bar. Closing the tree reveals a clickable Command-Shift-V reminder.

The sample editor and Notes are stand-ins for other applications. ⇧⌘V can open the tree while either editor is focused. Return pastes into the captured editor selection; the tree closes and returns focus. If no editor has been used, Notes is the default target. Drag text or image papers directly into the always-visible Notes window. Image records go to Notes even when the last target was the plain-text sample editor. Notes also accepts image files from a user paste or drop; blob URLs stay local and are revoked on clear/reset. Clicking the simulated desktop outside the tree's input surfaces dismisses the tree. Reset restores all twelve fixture records and clears Notes.

- UI labels, fixture records, sample text, image/file names, dates and feedback follow the browser language by default (English, Simplified Chinese, Traditional Chinese, Japanese or Korean; English fallback). One menu-bar selector overrides the whole page or restores automatic selection. Switching languages preserves user Notes, collected records and per-language sample drafts. Search normalizes Unicode to NFC.
- All demo data stays in memory. Only an explicit **Copy to system** click or ⌘C writes to the real clipboard. Images use a PNG ClipboardItem; an unavailable or denied API leaves the demo usable and reports failure. Demo Notes receives the actual example image. Copying and pasting close the tree, as in Swift.
- The sample photo has no OCR text; search matches its title. OCR fields, when provided by fixtures, are explicitly labeled. File records paste paths, not file contents. Vision, iCloud and phone pairing are described rather than simulated as connected services.
- Keyboard input respects text editing and composition. Browser-owned shortcuts have clickable alternatives. On narrow screens, the two persistent windows stack below the tree; there are no window-switching tabs.
- `native.ts`, `tree.ts`, `entrance.ts` and `preview.ts` port the native paper geometry, selection follow, page folds, finite settling tracks, preview follow and entrance curves. Retargets retain the presented pose and velocity; preview reading dimensions and zoom persist across records until closed. Rendering stops when settled or the page is hidden. Reduce Motion uses fades without travel. A failed reference image falls back to the previously exported static tree.
- GitHub statistics page through public Releases, count only `PasteHistory*.zip/.dmg/.pkg` installers, and choose the newest release with an arm64 installer. Verified results are cached for 30 minutes. API failures use cached data or the build snapshot; missing evidence is displayed as unavailable, never zero.

## Native interaction reference

| Swift source | Web behavior |
| --- | --- |
| `IvoryTreeScene` / `IvoryTreePaperView` / `IvoryPaperStyle` | Same projected branch anchors, 8 history slots + permanent phone slot, dimensions, fills, hole, typography, collision order, selected height and moving outline. |
| `HistoryKeyboardState` / `PanelController` | Space or ⌘Y previews (including a nonempty query); Shift-Space inserts a space. Arrows move one record; Page Up/Down move eight, retaining the offset where possible. Return pastes. ⌘C copies, ⌘P pins, ⌘W closes. ⌘1–9 paste the first nine filtered records, independent of the current group. |
| `HistoryViewModel` | Search selects the first result, pinning retains record identity, deletion selects the preceding record, and presentation resets selection. Boundary navigation bounces preview content. |
| `HistoryKeyboardState` | Delete removes a record only while navigating or with an empty query; otherwise it edits search. Composition owns its keys. Repeated Space/Delete/Escape do not replay actions. |
| `PaperPreviewFlight` / `PaperPreviewFollow` / `PreviewPanel` | Same 0.24 s open/close curves, interruptible velocity, hole anchoring, fixed reading layout, selection follow and local 1–2× magnification with a 0.15 s return. Click closes; text selection, scrolling and gestures do not. |
| `TreeEntrance` / layout controls | ⇧⌘V toggles the tree within the page. ⇧⌘M adjusts layout, ⌘R resets the preset/position while adjusting, Escape finishes. Small/standard/large presets and a drag handle are clickable. |

The browser remains a different host: it can consume ⌘W, ⌘R, ⌘1–9, ⌘Y or global shortcuts before JavaScript receives them. All actions have buttons. There are no system-wide hotkeys, accessibility paste into external applications, real file pasteboard objects, Vision OCR, iCloud or phone pairing in this static demo. File records copy example path text. Font rasterization also depends on the browser and OS. This implementation does not claim verified pixel-for-pixel or OS-level equivalence.

Validation for the native-alignment change: TypeScript/Vite build, architecture check and passive browser rendering inspection. The layout correction also removes whole-tree resizing on selection, retains the original input target, and places web-only controls outside the native surface. Per repository policy, interaction/UI regression suites and physical Safari/Chrome/trackpad/IME/drag verification require an explicit test request and were not run for this change.

Validation: TypeScript/Vite build, architecture and whitespace checks, plus focused browser inspection of image insertion, the global language selector, persistent windows and the clickable reopen reminder. External clipboard images, physical drag and cross-browser checks were not exercised. No interaction regression suite was run.

## Assets

`public/sample-lake.jpg` is a real photograph by Luca Bravo, *Boathouse on a mountain lake*, taken at Lago di Braies. The 1280px JPEG comes from [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Boathouse_on_a_mountain_lake_(Unsplash).jpg), which records its pre-June-2017 Unsplash publication under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). The source photograph is unchanged. The thumbnail, preview and Notes all contain the complete image without cropping.

`public/wallpaper-coast.jpg` is an original generated wallpaper, produced with the built-in imagegen tool and optimized as JPEG. Prompt: “Photorealistic 16:10 quiet coastal mountains at dawn, muted slate blue and warm gray, sea mist, pale granite foreground, quiet center for an ivory tree overlay; background only, no tree, birds, text, UI or logos.” The functional papers and controls are accessible HTML/DOM; only the decorative sculpture is rasterized.

Regenerate the tree assets on macOS from the repository root:

```sh
swift website/scripts/export-native-reference.swift Sources/PasteHistory/Resources/ivory_tree.scn website/public
```

Linux CI uses the committed `tree-native.png` and `native-tree.json`; it does not require SceneKit, WebGL or Blender. The earlier GLB export remains available in `export-tree.swift`.

## Deployment and native preview

`.github/workflows/website.yml` checks PRs and deploys main through GitHub Actions Pages on website changes, published Releases, or manual dispatch. Set the repository's Pages source to GitHub Actions. The public URL is only available after a successful deployment.

The native preview must be built from reviewed main containing PR #30. On an Apple Silicon Mac with Apple Development signing:

```sh
./scripts/package_preview.sh 1.0.0-beta.1
```

The script refuses ad-hoc fallback and verifies architecture, resources, signature and the extracted ZIP. Outputs are in `dist/release/1.0.0-beta.1/`. Publish ZIP and `SHA256SUMS.txt` with the prerelease, recording the exact commit, macOS 14+ requirement and lack of Apple notarization. This is not Developer ID distribution and may be blocked by macOS. Verify startup and actual paste with isolated test data before publishing; synthetic callback tests do not establish cross-app paste. Publishing or manually dispatching the website workflow refreshes the download snapshot.
