#!/bin/zsh
# 构建 release 并打包成 PasteHistory.app
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> swift build (release)"
swift build -c release

APP_DIR="PasteHistory.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp ".build/release/PasteHistory" "$APP_DIR/Contents/MacOS/PasteHistory"
cp "Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# 签名身份优先级：Apple Development（稳定，TCC 授权跨重建保留）> 自签名 PasteHistory > ad-hoc
# 说明：ad-hoc 签名没有稳定身份，TCC（辅助功能权限）按 cdhash 匹配，
# 每次重构建哈希变化 → 权限被判定失效、反复弹窗。用证书签名后只需首次授权一次。
SIGN_IDENTITY=""
if security find-identity -v -p codesigning 2>/dev/null | grep -q '"Apple Development'; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep '"Apple Development' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
elif security find-certificate -c PasteHistory ~/Library/Keychains/login.keychain-db >/dev/null 2>&1; then
    SIGN_IDENTITY="PasteHistory"
fi

if [ -n "$SIGN_IDENTITY" ]; then
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
    echo "==> 已用稳定身份签名: $SIGN_IDENTITY"
else
    codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || echo "(!) 签名失败，可忽略"
    echo "==> 警告：ad-hoc 签名，重建后辅助功能权限会失效"
fi

echo "==> 完成: $(pwd)/$APP_DIR"
