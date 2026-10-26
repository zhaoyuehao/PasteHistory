# PasteHistory desktop demo

A static Vite + TypeScript + Three.js website, served at `/PasteHistory/`. The sculpture uses meshes exported from the native `ivory_tree.scn`, including its five birds and surface-snapped attachment points. There is no application backend, clipboard polling, or persistent demo history.

```sh
cd website
npm ci
npm run dev                 # http://127.0.0.1:5173/PasteHistory/
npm test
npm run snapshot            # Refresh public GitHub statistics
npm run build
```

## Experience

The first visit shows the tree with three clipboard kinds, a download button, and centered GitHub statistics. Selecting a paper reveals preview, search and history tools. Notes appears when pasting. The menu's copy-sample window provides text, image and file examples; **Load more examples** enables the full paginated dataset. Reset restores the three-paper welcome state and clears Notes.

- All demo data stays in memory. Only **Copy to system** writes to the real clipboard, after a click. Images copy their title to the system clipboard; demo Notes receives the actual example image.
- The sample photo has no OCR text; search matches its title. OCR fields, when provided by fixtures, are explicitly labeled. File records paste paths, not file contents. Vision, iCloud and phone pairing are described rather than simulated as connected services.
- Keyboard input respects text editing and composition. Browser-owned shortcuts have clickable alternatives. Mobile uses one window at a time with touch controls.
- Tree selection and preview positions use interruptible springs. Rendering stops when settled or the page is hidden; Reduce Motion settles immediately. `?fallback=1` exercises the static sculpture fallback.
- GitHub statistics page through public Releases, count only `PasteHistory*.zip/.dmg/.pkg` installers, and choose the newest release with an arm64 installer. Verified results are cached for 30 minutes. API failures use cached data or the build snapshot; missing evidence is displayed as unavailable, never zero.

## Assets

`public/sample-lake.jpg` is a real photograph by Luca Bravo, *Boathouse on a mountain lake*, taken at Lago di Braies. The 1280px JPEG comes from [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Boathouse_on_a_mountain_lake_(Unsplash).jpg), which records its pre-June-2017 Unsplash publication under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). The source photograph is unchanged. The thumbnail uses CSS cropping; the preview and Notes display the complete image.

`public/wallpaper-coast.jpg` is an original generated wallpaper, produced with the built-in imagegen tool and optimized as JPEG. Prompt: “Photorealistic 16:10 quiet coastal mountains at dawn, muted slate blue and warm gray, sea mist, pale granite foreground, quiet center for an ivory tree overlay; background only, no tree, birds, text, UI or logos.” The functional UI is HTML/DOM and WebGL, not a flattened mockup.

Regenerate the tree assets on macOS from the repository root:

```sh
swift website/scripts/export-tree.swift Sources/PasteHistory/Resources/ivory_tree.scn website/public
```

Linux CI uses the committed GLB and PNG and does not require SceneKit or Blender.

## Deployment and native preview

`.github/workflows/website.yml` checks PRs and deploys main through GitHub Actions Pages on website changes, published Releases, or manual dispatch. Set the repository's Pages source to GitHub Actions. The public URL is only available after a successful deployment.

The native preview must be built from reviewed main containing PR #30. On an Apple Silicon Mac with Apple Development signing:

```sh
./scripts/package_preview.sh 1.0.0-beta.1
```

The script refuses ad-hoc fallback and verifies architecture, resources, signature and the extracted ZIP. Outputs are in `dist/release/1.0.0-beta.1/`. Publish ZIP and `SHA256SUMS.txt` with the prerelease, recording the exact commit, macOS 14+ requirement and lack of Apple notarization. This is not Developer ID distribution and may be blocked by macOS. Verify startup and actual paste with isolated test data before publishing; synthetic callback tests do not establish cross-app paste. Publishing or manually dispatching the website workflow refreshes the download snapshot.
