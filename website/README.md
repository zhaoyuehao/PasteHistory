# PasteHistory desktop demo

A static Vite + TypeScript + Three.js website, served at `/PasteHistory/` on GitHub Pages or `/` on Cloudflare Pages. The sculpture is rendered by SceneKit from the native `ivory_tree.scn`, with the camera, material, lighting, five birds and surface-snapped attachment points from native main `0765399`. Three.js projects the exported world-space anchors; accessible DOM papers remain interactive. There is no application backend, clipboard polling, or persistent demo history.

```sh
cd website
npm ci
npm run dev                 # http://127.0.0.1:5173/PasteHistory/
npm test
npm run snapshot            # Refresh public GitHub statistics
npm run build
```

## Cloudflare Pages

Build with root-relative asset URLs for Cloudflare while keeping the default GitHub Pages build under `/PasteHistory/`:

```sh
cd website
npm ci
npm run snapshot
npm run build:cloudflare
npx wrangler pages deploy dist --project-name pastehistory --branch main
```

Authenticate Wrangler with your own Cloudflare account before deploying. Upload only `dist`; credentials are never included in the site. This is a direct-upload deployment; the GitHub Pages workflow remains separate.

## Experience

The first visit opens the native default tree layout with eight history records, a permanent Phone Sync card and the root search tag. The same frame and point sizes remain in use when selecting, searching and previewing: there is no separate three-record hero, whole-tree zoom or layout transition. The download button is centered below the root search tag, followed by a quiet GitHub link and statistics. Copy Samples and Notes stay visible on either side of the tree. The shortcut guide and drag hint live inside Notes. The menu bar has a compact globe/current-language selector. The auxiliary Actions menu, layout editing controls, demo reset and bottom toolbar are removed. Notes has a short drop/paste prompt and four shortcut rows; Copy Samples shows a short editable sentence and photograph together, each with its own copy button. Closing the tree reveals a clickable Command-Shift-V reminder.

The desktop sizes the tree from the available height and width, without a fixed render-size cap or a dependency on side-window width. Its native 880 × 920 frame scales uniformly; positioning reserves the central 660-point band containing the sculpture and papers rather than counting transparent frame margins as visible content. Side windows remain compact portrait golden rectangles (up to 230 px wide), aligned with the tree center. The gap from that central band is window width / φ⁴ (φ ≈ 1.618); the complete group is centered with at least φ times that gap at the outer edges. History papers now use width / height = φ, including during selected-size transitions; the phone paper uses the portrait equivalent. This is a deliberate website geometry adjustment from Swift. Copy controls use φ² : 1 and the download control φ³ : 1 to keep labels readable without oversized button height. Text and image samples are shown together with one copy button each; there are no sample tabs or file sample creation. Existing file history records remain supported. Below 760 px, the windows stack.

The sample editor and Notes are stand-ins for other applications. ⇧⌘V can open the tree while either editor is focused. Return pastes into the captured editor selection; the tree closes and returns focus. If no editor has been used, Notes is the default target. Drag text or image papers directly into the always-visible Notes window. Image records go to Notes even when the last target was the plain-text sample editor. Notes also accepts image files from a user paste or drop; blob URLs stay local and are revoked when Notes is cleared. Clicking the simulated desktop outside the tree's input surfaces dismisses the tree. Reloading the page starts a fresh in-memory session.

- UI labels, fixture records, sample text, image/file names, dates and feedback follow the browser language by default (English, Simplified Chinese, Traditional Chinese, Japanese or Korean; English fallback). The menu-bar selector lists only the five named languages, with the detected initial language selected. Choosing a language updates the whole page and saves only that preference in localStorage, so reloads retain it. Unavailable storage or an invalid stored value falls back to browser detection. Phone Sync labels have explicit paper insets and can wrap across languages. Switching languages preserves user Notes, collected records and per-language sample drafts. Search normalizes Unicode to NFC.
- All demo data stays in memory. Only an explicit **Copy to system** click or ⌘C writes to the real clipboard. Images use a PNG ClipboardItem; an unavailable or denied API leaves the demo usable and reports failure. Demo Notes receives the actual example image. Copying and pasting close the tree, as in Swift.
- The sample photo has no OCR text; search matches its title. OCR fields, when provided by fixtures, are explicitly labeled. File records paste paths, not file contents. Vision, iCloud and phone pairing are described rather than simulated as connected services.
- Keyboard input respects text editing and composition. Browser-owned shortcuts have clickable alternatives. On narrow screens, the two persistent windows stack below the tree; there are no window-switching tabs.
- `native.ts`, `tree.ts`, `entrance.ts` and `preview.ts` port the native paper geometry, selection follow, page folds, finite settling tracks, preview follow and entrance curves. Retargets retain the presented pose and velocity; preview reading dimensions and zoom persist across records until closed. Rendering stops when settled or the page is hidden. Reduce Motion uses fades without travel. A failed reference image falls back to the previously exported static tree.
- GitHub statistics page through public Releases, count only `PasteHistory*.zip/.dmg/.pkg` installers, and choose the newest release with an arm64 installer. Verified statistics are cached for 30 minutes. The download button opens the actual installer attachment directly, without a dialog; each normal click refreshes Releases instead of trusting the statistics cache. It selects the newest published release with an arm64 installer, including previews. API failures use cached data or the build snapshot and identify a cached download; missing installers are shown as unpublished, with no fabricated URL. Missing statistics are displayed as unavailable, never zero.

## Native interaction reference

| Swift source | Web behavior |
| --- | --- |
| `IvoryTreeScene` / `IvoryTreePaperView` / `IvoryPaperStyle` | Native projected branch anchors, 8 history slots + permanent phone slot, fills, hole, typography and moving outline. Website papers use golden rectangles; selection grows both dimensions together and collision placement uses those dimensions. |
| `HistoryKeyboardState` / `PanelController` | Space or ⌘Y previews (including a nonempty query); Shift-Space inserts a space. Arrows move one record; Page Up/Down move eight, retaining the offset where possible. Return pastes. ⌘C copies, ⌘P pins, ⌘W closes. ⌘1–9 paste the first nine filtered records, independent of the current group. |
| `HistoryViewModel` | Search selects the first result, pinning retains record identity, deletion selects the preceding record, and presentation resets selection. Boundary navigation bounces preview content. |
| `HistoryKeyboardState` | Delete removes a record only while navigating or with an empty query; otherwise it edits search. Composition owns its keys. Repeated Space/Delete/Escape do not replay actions. |
| `PaperPreviewFlight` / `PaperPreviewFollow` / `PreviewPanel` | Same 0.24 s open/close curves, interruptible velocity, hole anchoring, fixed reading layout, selection follow and local 1–2× magnification with a 0.15 s return. Click closes; text selection, scrolling and gestures do not. |
| `TreeEntrance` | ⇧⌘V toggles the tree within the page; the menu-bar brand and closed-tree reminder are clickable. The demo uses a fixed responsive layout; native layout editing is not exposed. |

The browser remains a different host: it can consume ⌘W, ⌘R, ⌘1–9, ⌘Y or global shortcuts before JavaScript receives them. The auxiliary action menu is intentionally absent. Paper preview and drag-to-Notes remain clickable/direct actions; history pin/delete/page commands are keyboard-driven. There are no system-wide hotkeys, accessibility paste into external applications, real file pasteboard objects, Vision OCR, iCloud or phone pairing in this static demo. File records copy example path text. Font rasterization also depends on the browser and OS. This implementation does not claim verified pixel-for-pixel or OS-level equivalence.

Passive wide-screen inspection measured a 996.70 × 1042 px tree frame at a 2275 × 1233 CSS viewport, up from the previous fixed 602.15 px width. The root download links remained within the viewport. Both copy controls remain visible together.

Validation for the native-alignment change: TypeScript/Vite build, architecture check and passive browser rendering inspection. The layout correction also removes whole-tree resizing on selection, retains the original input target, and places web-only controls outside the native surface. Per repository policy, interaction/UI regression suites and physical Safari/Chrome/trackpad/IME/drag verification require an explicit test request and were not run for this change.

Validation: TypeScript/Vite build, architecture and whitespace checks, plus focused browser inspection of image insertion, the global language selector, persistent windows and the clickable reopen reminder. External clipboard images, physical drag and cross-browser checks were not exercised. No interaction regression suite was run.

## Assets

`public/wallpaper-slate.jpg` is the active original wallpaper, generated with the built-in imagegen tool and encoded as JPEG. Its low-detail center and dark slate palette give the ivory tree contrast; download metadata and GitHub links use light text. It is inspired by abstract desktop wallpapers and is not an Apple-provided asset.

Final edit prompt: “Edit this wallpaper only: make it substantially darker, elegant medium-dark desaturated slate blue and charcoal gray, like a quiet macOS dark desktop wallpaper. Keep the original wide aspect ratio, gentle abstract satin dunes, smooth gradients, broad empty central field and exact basic composition. Center should be a uniform subdued slate blue, around #354858, so an ivory white tree and light paper tags placed on top stand out. Lower folds in charcoal blue-gray with a very subtle warm gray edge, never bright white. Preserve softly illuminated form and exquisite subtle texture; do not crush shadows to black. No saturated cyan, purple, neon, glare, objects, trees, text, UI or logos. Output the wallpaper alone.”

`public/sample-lake.jpg` is a real photograph by Luca Bravo, *Boathouse on a mountain lake*, taken at Lago di Braies. The 1280px JPEG comes from [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Boathouse_on_a_mountain_lake_(Unsplash).jpg), which records its pre-June-2017 Unsplash publication under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). The source photograph is unchanged. The copy sample, preview and Notes contain the complete image without cropping.

`public/wallpaper-coast.jpg` is the unused earlier generated wallpaper, produced with the built-in imagegen tool and optimized as JPEG. Prompt: “Photorealistic 16:10 quiet coastal mountains at dawn, muted slate blue and warm gray, sea mist, pale granite foreground, quiet center for an ivory tree overlay; background only, no tree, birds, text, UI or logos.” The functional papers and controls are accessible HTML/DOM; only the decorative sculpture is rasterized.

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

The script refuses ad-hoc fallback and verifies architecture, resources, signature and the extracted ZIP. Outputs are in `dist/release/1.0.0-beta.1/`. Upload ZIP and `SHA256SUMS.txt` to a draft prerelease first, recording the exact commit, macOS 14+ requirement and lack of Apple notarization. This is not Developer ID distribution and may be blocked by macOS. Keep the release in draft until startup and actual paste have been verified with isolated test data; synthetic callback tests do not establish cross-app paste. Publishing or manually dispatching the website workflow refreshes the download snapshot.
