#!/usr/bin/env python3
"""Guard the requested UI/motion/data boundary, not incidental UI strings."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1] / "Sources/PasteHistory"
errors = []
ui_symbols = r"\b(?:Motion|TreeMotion|PaperPreviewFlight|PaperPose|PaperFlightView|TreeEntrance|SettlingTrack|HistorySelectionMotion|Palette|Scale|IvoryPaperStyle|PreviewContentView|PanelController|HistoryPanel|IvoryTreeSceneView|Toast|WebSyncPage|NSWindow|NSPanel|NSView|NSHostingView|NSHostingController|withAnimation)\b"
for layer in ("Domain", "Application", "Infrastructure"):
    for source in (root / layer).rglob("*.swift"):
        text = source.read_text()
        # Comments describe the boundary but are not dependencies.
        code = re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S)
        forbidden_imports = {"SwiftUI", "SceneKit"}
        if layer == "Domain":
            forbidden_imports.add("AppKit")
        imports = set(re.findall(r"^import (\w+)", code, flags=re.M))
        for name in imports & forbidden_imports:
            errors.append(f"{source.relative_to(root)} imports {name}")
        for match in re.finditer(ui_symbols, code):
            errors.append(f"{source.relative_to(root)} depends on UI/motion symbol {match[0]}")
for source in (root / "Presentation").rglob("*.swift"):
    if re.search(r"\b(?:sqlite3_\w+|CGImageSource\w*)\s*\(|\bFileManager\.default", source.read_text()):
        errors.append(f"{source.relative_to(root)} performs storage/image decoding in a view")
if errors:
    raise SystemExit("Architecture boundary failed:\n" + "\n".join(errors))
print("PASS: domain/application/infrastructure do not depend on UI or animation; decoding/storage stay outside presentation")
