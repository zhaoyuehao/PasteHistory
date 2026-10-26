#!/bin/zsh
# Build the public Apple Silicon preview locally. No credentials enter GitHub Actions.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-1.0.0-beta.1}"
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+$' ]] || { print -u2 'Expected a preview version, e.g. 1.0.0-beta.1'; exit 1; }
[[ "$(uname -m)" == arm64 ]] || { print -u2 'Build this preview on Apple Silicon.'; exit 1; }
IDENTITIES=$(security find-identity -v -p codesigning)
[[ "$IDENTITIES" == *'"Apple Development:'* ]] || { print -u2 'Apple Development identity required; refusing ad-hoc fallback.'; exit 1; }
./scripts/build_app.sh
APP=PasteHistory.app
codesign --verify --deep --strict "$APP"
SIGNATURE=$(codesign -dvv "$APP" 2>&1)
[[ "$SIGNATURE" == *'Authority=Apple Development:'* ]] || { print -u2 'Unexpected signing identity.'; exit 1; }
[[ "$(lipo -archs "$APP/Contents/MacOS/PasteHistory")" == arm64 ]] || { print -u2 'Expected arm64 binary.'; exit 1; }
[[ -f "$APP/Contents/Resources/PasteHistory_PasteHistory.bundle/ivory_tree.scn" ]] || { print -u2 'Missing bundled tree.'; exit 1; }
OUT="dist/release/$VERSION"
mkdir -p "$OUT"
ZIP="PasteHistory-$VERSION-macos-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$ZIP"
VERIFY=$(mktemp -d "${TMPDIR:-/tmp/}pastehistory-release.XXXXXX")
trap 'rm -rf "$VERIFY"' EXIT
ditto -x -k "$OUT/$ZIP" "$VERIFY"
codesign --verify --deep --strict "$VERIFY/PasteHistory.app"
(cd "$OUT" && shasum -a 256 "$ZIP" > SHA256SUMS.txt)
print "Preview ready: $OUT/$ZIP"
print 'Apple Development signed, NOT notarized. Publish as a prerelease with installation limitations.'
