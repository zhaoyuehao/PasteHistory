# Development

[Home](../README.md) · [Contributor rules](../AGENTS.md) · [Sync](sync.md) · [Tree resources](tree.md)

Run commands from the repository root. Requires macOS 14+, Swift 6 (the target uses Swift 5 language mode), and Python 3 for boundary checks. Blender is only needed for model export; Node.js is only needed for crypto cross-checks.

## Build

```sh
./scripts/build_app.sh
codesign -dv --verbose=4 PasteHistory.app
open PasteHistory.app
```

The script packages the executable, Info.plist and SwiftPM resource bundle. Use Apple Development signing for regular builds; verify `Authority` instead of assuming the fallback meets that requirement. If Accessibility authorization stops surviving rebuilds, check the signature and remove duplicate app entries in System Settings before authorizing the current app.

After moving the checkout, a PCH/module-cache path error requires deleting `.build` and rebuilding. No Xcode project is used.

## Architecture

One executable target, with recursively discovered sources under [`Sources/PasteHistory/`](../Sources/PasteHistory/):

| Directory | Responsibility |
| --- | --- |
| `Domain/` | Records, content fingerprints and search fields; no UI imports |
| `Application/` | ClipStore, settings, selection, keyboard rules and feedback events |
| `Infrastructure/` | SQLite persistence; clipboard/AX/drag adapters; OCR/media loading; iCloud/HTTP; diagnostics |
| `Presentation/` | Tree, history search, preview, window/input routing, sync UI, styles and animations |
| `Shared/Localization.swift` | Native localized strings; the web page handles its own localization |
| `Resources/ivory_tree.scn` | Bundled SceneKit model |
| `main.swift` | Composition, service lifecycle, menu, global shortcut and startup arguments |

ClipboardMonitor polls every 0.4 seconds and forwards supported content to ClipStore, which writes SQLite and images, schedules OCR and exports iCloud changes. Search is debounced by 250ms and loads 60 records per batch; the tree presents eight at a time. PreviewMediaLoader receives its image directory by injection. Services emit UserFeedback; the entry point connects it to Toast and injects HTML into the HTTP server.

Application state publishes results and input timing, not animations. Presentation owns motion and layout; storage and image decoding stay in Infrastructure. HTTP routing and encryption use a dedicated queue and read connection, then dispatch writes asynchronously to the main queue. See [implementation constraints](../AGENTS.md#implementation-constraints).

## Validation

Use change-appropriate builds and static checks by default. Run interaction/UI regression tests only when explicitly requested by the user; this includes the full suite, focused variants, interactive runs and drag tests. Structural or UI changes alone do not trigger regression runs.

After structural changes:

```sh
python3 scripts/check_architecture.py
```

When the user requests the full interaction regression suite:

```sh
mkdir -p .build
./scripts/test_tree_ui.sh
```

Native tests require a logged-in macOS graphical session. UI tests use synthetic data and temporary SQLite, not user history or the general clipboard. Build/compile logs are `.build/tree-ui-build.log` and `.build/tree-ui-compile.log`.

Paper motion uses one state `(x, v, r)` for flight, following and gesture release:
`r' = (goal-r)/τ`, `x' = v`, `v' = ω²(r-x)-2ωv`, with `ω = 20 s⁻¹` and
`τ = 20 ms`. The exact exponential solution advances by display timestamps;
changing the goal preserves position, velocity and acceleration. Settling uses
position/velocity tolerances rather than a fixed playback deadline. Normal motion
reaches 95% in about 262 ms; the low-speed tail remains interruptible. Reduce Motion
retains a short in-place content dissolve. Each card keeps its original window,
renderer, shell and shadow through expansion, reading and collapse. A live reading
NSView scales and rotates in fixed logical coordinates; there is no reading bitmap
or endpoint window handoff. AppKit owns native document backing layers; the renderer
does not recursively override their content scales. Compact face caches refresh
only when content or logical layout changes. The tree updates the compact return
pose while the preview owns the visible window geometry. Selecting another record
transfers the live document and motion state to that card's existing window.
Reading input becomes eligible before final settling once expansion, remaining
position/size error and speed are sufficiently small; eligibility never activates
the window. Closing revokes it immediately. The content dissolve spans 25–100%
of expansion so the reading face continues appearing as the paper approaches its
final size, rather than finishing at 85%.

The numeric check needs no desktop:

```sh
swiftc Sources/PasteHistory/Presentation/Animation/DampedMotion.swift scripts/test_damped_motion.swift -o .build/test-damped-motion
.build/test-damped-motion
```

When animation regression is requested, `./scripts/test_tree_ui.sh --paper-motion`
checks persistent window/document identity, continuous reversal, gesture routing,
native pin coordinate conversion and bounded windows.
Its `.build/paper-motion-frames.csv` measures display callback intervals and CPU
work, not compositor presentation or physical input latency.

For a user-driven motion timing capture, launch the signed app with
`--trace-paper-motion`. Each opening/closing buffers at most 512 numeric samples
in memory, then asynchronously writes callback intervals, first-callback wait,
geometry-update CPU work and shadow invalidation CPU work to
`~/Library/Application Support/PasteHistory/paper_motion.log` (bounded to 512 KB).
No record text, IDs or images are captured. Callback cadence is not compositor
FPS; large gaps with cheap callbacks indicate work outside the measured callback.
The first display callback establishes animation time zero so initial AppKit
preparation cannot consume the opening's visible travel. Reading layout is
prepared before motion; per-frame transforms do not force subtree layout. Use
`./scripts/test_tree_ui.sh --preview-text` for full-text/reading-position checks.

| Change | Additional validation |
| --- | --- |
| Documentation | Relative links, paths, command syntax and `git diff --check` |
| UI, input or motion | Build and static checks; `./scripts/test_tree_ui.sh --interactive` only when explicitly requested |
| Cross-app drag | Build and static checks; `./scripts/test_drag_ui.sh` (optionally `--drag-image` or `--drag-files`) only when explicitly requested |
| Model | [Geometry check](tree.md#geometry-check) and app packaging; UI regression only when explicitly requested |
| Phone encryption | [Crypto checks](sync.md#crypto-checks) against both implementations |
| Packaging/resources | `./scripts/build_app.sh`, signature inspection and launch |

UI tests verify paste callback routing, not actual paste into another app. When requested, physical trackpad gestures, cross-process dragging and target-app pasting need real-device validation. Do not add assertions for incidental wording or implementation fields.

## Startup and maintenance

Quit the existing app before passing startup arguments. Reopening an existing process reveals the tree but does not replay arguments. These commands use **real history**; paste options send input to the target app, and deletion can propagate to iCloud. The process remains running after maintenance.

```sh
PasteHistory.app/Contents/MacOS/PasteHistory --show
```

| Argument | Effect |
| --- | --- |
| `--show` | Open the tree on launch |
| `--trace-anchor` | Also send diagnostic trace output to NSLog |
| `--show-pair` | Open the standalone pairing diagnostic panel; normal access is the tree card |
| `--print-ax` | Request authorization if needed and write `ax_status.txt` |
| `--paste-latest` | Paste the most recent record; focus a test input first |
| `--smoke-panel-paste` | Open history and exercise the paste route; focus a test input first |
| `--smoke-preview` | Open, follow selection and close preview; needs at least two records |
| `--purge-ids "uuid1,uuid2"` | Delete valid record UUIDs; active iCloud sync also removes record files and writes tombstones |
| `--restore-images` | Restore missing originals from an active, readable iCloud sync directory |

Verify the resulting data/logs rather than treating process startup as successful maintenance.

## Diagnostics and recovery

Data and logs live in `~/Library/Application Support/PasteHistory/`. `anchor_trace.log` is rewritten after 200,000 bytes; `preview-pinch` logs gesture phase, scale and window details, not clipboard text. `ax_status.txt` contains `trusted` or `not-trusted`.

- **Copy works, paste does not:** check Accessibility, signing and the `autoPaste` preference. There is no automatic-paste menu toggle in the current UI.
- **Preview pinch fails:** keep the pointer inside the preview, inspect `preview-pinch`, and reproduce with a physical trackpad. Non-key previews use a scoped local magnify monitor; view recognizers alone previously required clicking for focus.
- **Reopened tree disappears:** preserve generation guards that invalidate delayed activation/animation callbacks; guard visibility in resign-key handling.
- **Phone connection fails:** follow [connection checks](sync.md#connection-checks).
- **Missing originals:** wait for iCloud files to arrive before `--restore-images`.

Quit before backing up the entire data directory, including `images/`, SQLite and any existing `-wal`/`-shm` files. Do not copy only a live SQLite main file. Account for remote tombstones before restoring an old database: image restoration does not recover deleted records or undo deletions.
