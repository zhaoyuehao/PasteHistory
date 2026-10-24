#!/bin/zsh
# Isolated native drag source + independent receiver; no user clipboard/history.
# Drag the focused fixture to the receiver. --drag-image / --drag-files select type.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=.build/DragReceiver.app
mkdir -p "$APP/Contents/MacOS"
swiftc -parse-as-library scripts/test_drag_receiver.swift -o "$APP/Contents/MacOS/DragReceiver" -framework AppKit
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.pastehistory.drag-receiver</string><key>CFBundleName</key><string>DragReceiver</string><key>CFBundleExecutable</key><string>DragReceiver</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
"$APP/Contents/MacOS/DragReceiver" &
receiver_pid=$!
trap 'kill "$receiver_pid" 2>/dev/null || true' EXIT INT TERM
./scripts/test_tree_ui.sh --drag-interactive "$@"
