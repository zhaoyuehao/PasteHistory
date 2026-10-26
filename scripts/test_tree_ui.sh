#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check_architecture.py
swift build > .build/tree-ui-build.log 2>&1
BIN_DIR=$(swift build --show-bin-path)
APP=.build/IvoryTreePreview.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SOURCES=(Sources/PasteHistory/**/*.swift)
SOURCES=("${(@)SOURCES:#Sources/PasteHistory/main.swift}")
HARNESS=scripts/test_tree_ui.swift
if [[ "${1:-}" == "--preview-text" ]]; then
  HARNESS=scripts/test_preview_text.swift
  shift
fi
swiftc -swift-version 5 -parse-as-library "${SOURCES[@]}" \
  "$BIN_DIR/PasteHistory.build/DerivedSources/resource_bundle_accessor.swift" "$HARNESS" scripts/test_paper_motion.swift \
  -o "$APP/Contents/MacOS/IvoryTreePreview" -framework AppKit -framework SceneKit -framework Carbon -framework Vision -lsqlite3 \
  > .build/tree-ui-compile.log 2>&1
cp -R "$BIN_DIR/PasteHistory_PasteHistory.bundle" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.pastehistory.ivory-tree-smoke</string>
<key>CFBundleName</key><string>IvoryTreePreview</string>
<key>CFBundleExecutable</key><string>IvoryTreePreview</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
"$APP/Contents/MacOS/IvoryTreePreview" "$@"
