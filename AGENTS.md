# Contributor instructions

PasteHistory is a macOS menu bar app built as one SwiftPM executable and packaged by script. Read [README.md](README.md), [development](docs/development.md), [sync](docs/sync.md) and [tree resources](docs/tree.md) as needed. English is the default documentation language; keep [README_ZH.md](README_ZH.md) aligned with user-facing changes. Do not add redundant indexes, historical design proposals or generated preview images.

## Branch and account workflow

- Start every change from the latest remote `main`. Fetch before editing, fast-forward local `main` to the fetched revision, then create a new `codex/*` branch. Preserve existing work; reuse a suitable clean worktree when possible.

  ```sh
  git -c credential.helper="!$HOME/Documents/PasteHistory/.git/credential-personal.sh" fetch https://github.com:443/zhaoyuehao/PasteHistory.git main
  ```

- All changes go through a PR: branch, commit, push, `gh pr create`, review, then merge. **Never push directly to main.** If main advances, fetch and rebase onto it; do not force-push to resolve upstream drift.
- Use personal account **zhaoyuehao**, not company account `zhaoyuehao_codeck`. Repository configuration clears inherited credential helpers, uses `.git/credential-personal.sh`, and rewrites both HTTPS and SSH repository URLs to `https://github.com:443/zhaoyuehao/PasteHistory.git` to bypass the global company SSH rewrite. Normal `git push` should work without custom credentials.
- Verify the active CLI account before creating the PR. Use `gh auth switch --user zhaoyuehao` if needed; this is global, so switch back to `zhaoyuehao_codeck` when returning to company repositories.
- Check only the username, never print the full credential response or token:

  ```sh
  printf 'protocol=https\nhost=github.com\npath=zhaoyuehao/PasteHistory.git\n' | git credential fill | sed -n 's/^username=/username=/p'
  ```

- If repository credential routing is not applied, explicitly select the existing helper (it must itself be functional):

  ```sh
  git -c credential.helper="!$HOME/Documents/PasteHistory/.git/credential-personal.sh" push https://github.com:443/zhaoyuehao/PasteHistory.git HEAD
  ```

  The `!` and absolute helper path are required; the helper obtains the personal token through `gh auth token --user zhaoyuehao`. Explicit-URL fetch/push may leave `origin/main` stale: verify with `git ls-remote --heads` against that URL before correcting a tracking ref.

## Build and validation

Use `./scripts/build_app.sh` and `open PasteHistory.app`. **Regular builds must use Apple Development signing**; the script's self-signed/ad-hoc fallback does not meet the TCC stability requirement. Delete `.build` after a checkout move if cached module paths fail.

After structural changes, run `python3 scripts/check_architecture.py` and `./scripts/test_tree_ui.sh` (create `.build` first). UI tests require a graphical desktop. Use [change-specific checks](docs/development.md#validation); avoid low-signal assertions for wording, formatting or incidental fields. Actual trackpad input, cross-app paste and native dragging still need physical validation.

## Implementation constraints

- Keep one executable target and recursive source discovery. Domain must not import UI frameworks. Application publishes state and input timing, never `withAnimation` or motion tokens. Infrastructure may use AppKit system adapters but must not create windows or depend on Presentation. Presentation owns layouts and animations, never direct SQLite/file access or image decoding. Inject media directories, HTML and feedback presenters at composition boundaries.
- **Every state transition must feel damped: a visibly moving object, sufficient travel and continuous interruption.** This takes priority over density. Do not replace moving selection feedback with independent crossfades or disable animation during repeated navigation; shorten the spring instead. Preserve the system Reduce Motion path. Keep motion in `Presentation/Animation/` and style in `Presentation/Style/`.
- Image cards show images or placeholders, never OCR as an image substitute. OCR remains searchable and readable in expanded previews.
- Preview scales the whole paper uniformly, keeps its logical reading layout and preserves scale across records until closed. It remains non-key so search retains keyboard focus. Scope local magnify monitoring to the preview window and its bounds, consume events once, and remove monitoring on close. Never use global gesture interception or redirect other windows' input.
- Decorative tree windows ignore mouse events. Only cards/search/layout controls receive input; do not intercept or replay clicks on other apps. Dragging copies only, preserves source files and the general clipboard, and handles cancellation and target focus correctly. The Phone Sync card stays outside history storage/actions.
- Preserve generation guards and visibility checks around delayed activation and interrupted transitions. Do not let stale close callbacks dismiss a newly opened window.
- HTTP routing/encryption must stay off MainActor on `com.verdent.pastehistory.websync`, with an independent SQLite read connection and main-queue asynchronous writes. Menus and modal loops must not block network responses.
- Never synchronously dispatch to the SQLite serial queue from within itself. Use non-dispatching private helpers for internal queries.
- Serialize top-level strings with JSONEncoder, not NSJSONSerialization. Vision Chinese OCR requires `.accurate` and explicit `zh-Hans`, `zh-Hant`, `en-US` languages.
- Phone HTTP APIs need fallbacks; localhost capabilities do not prove phone compatibility. Encryption changes require both-end protocol checks and [Node cross-validation](docs/sync.md#crypto-checks). Do not imply HTTPS protection or local encrypted storage.
- Explain model, database, sync protocol and clipboard payload changes explicitly; do not hide them inside visual work. Maintenance commands operate on real data: follow [startup prerequisites](docs/development.md#startup-and-maintenance).
