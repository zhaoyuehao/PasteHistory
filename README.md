# PasteHistory

[简体中文](README_ZH.md)

A macOS menu bar clipboard history app. Press **⇧⌘V** to search text, images and file paths on a desktop tree, then press Return to paste into the original app. Includes on-device OCR, iCloud sync between Macs and local-network phone access.

## Build and run

Requires **macOS 14+** and a **Swift 6 toolchain**. No Xcode project or runtime Blender installation is needed.

```sh
./scripts/build_app.sh
open PasteHistory.app
```

The script builds and packages the app, then selects Apple Development, a local PasteHistory certificate, or ad-hoc signing in that order. Use **Apple Development** for regular builds: ad-hoc rebuilds can invalidate Accessibility authorization.

Allow PasteHistory in **System Settings → Privacy & Security → Accessibility** for automatic paste. Without authorization, the selected content is copied for manual ⌘V. The app stays in the menu bar, with no Dock icon.

## Use

Copy content in another app, open the tree and type to search. Each group contains eight history cards plus a permanent **Phone Sync** card. The tree opens centered on the screen under the pointer; decorative branches and empty space let clicks pass through.

Click a history card to preview it. Click the expanded paper to close it; text selection, scrolling and pinching do not close it. Pinching inside the preview scales the whole paper without taking keyboard focus from search. Drag history cards into compatible apps to copy their content without moving source files.

| Action | Shortcut |
| --- | --- |
| Toggle history globally | ⇧⌘V |
| Select / change group | ↑ / ↓; Page Up / Page Down (fn↑ / fn↓) |
| Toggle preview | Space / ⌘Y |
| Insert a space in search | Shift-Space |
| Paste / copy only | Return / ⌘C |
| Paste result 1–9 | ⌘1–9, indexed across search results, not the current group |
| Pin / unpin | ⌘P |
| Delete a record | Delete when navigating or when search is empty; otherwise edit search text |
| Close preview, then history | Esc; IME composition and native dragging handle cancellation first |
| Close history | ⌘W or click another app |
| Adjust layout | ⇧⌘M; ⌘R resets, Esc finishes |

Layout changes preserve the size preset; moving the tree only affects the current opening. Input-method composition keeps its own navigation and confirmation keys. The Phone Sync card is not a history record: it cannot be deleted, pinned or dragged out.

## Sync

- **Phone:** click the tree's Phone Sync card and scan the QR code on the same reachable local network. Paste text into the web page to send it to the Mac; copy text/file paths or save images from Mac history. Refreshing the QR code invalidates old pairing sessions. HTTP phone pages cannot automatically read the clipboard or work offline.
- **Other Macs:** use the same Apple account with iCloud Drive available. Sync is enabled by default; the menu shows a retry item when unavailable. Records, images and deletions propagate through `iCloud Drive/PasteHistory/` as files arrive.

The phone page searches at most 300 downloaded records. File entries contain paths, not arbitrary file contents. See [sync details and security boundaries](docs/sync.md).

## Data and privacy

History lives in `~/Library/Application Support/PasteHistory/`: `history.sqlite` and its WAL files, plus `images/`. Preferences use the `com.verdent.pastehistory` UserDefaults domain. Quit the app before backing up the complete data directory; iCloud sync is not an independent backup.

OCR runs locally for Simplified Chinese, Traditional Chinese and English. Search also covers text, file paths, source apps and image classification labels. Password-manager apps and concealed/transient clipboard markers are ignored by default; unmarked sensitive text can still be recorded. Pause recording from the menu when needed.

**Local and iCloud files have no application-level encryption.** Phone payload encryption does not provide HTTPS protection; use a trusted local network. Universal Clipboard content is recorded when it reaches the Mac, not as a continuous history of phone activity.

## Development

- [Development](docs/development.md): architecture, tests, diagnostics and maintenance commands.
- [Sync](docs/sync.md): pairing, wire format, limitations and crypto checks.
- [Tree resources](docs/tree.md): interaction constraints, model export and geometry checks.
- [Contributor rules](AGENTS.md): branch workflow and implementation requirements.

English is the default documentation language. Keep [README_ZH.md](README_ZH.md) aligned with user-facing changes; keep generated previews and design experiments out of the source tree.
