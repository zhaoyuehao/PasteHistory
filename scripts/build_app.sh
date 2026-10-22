#!/bin/zsh
# 构建 release 并打包成 PasteHistory.app
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> swift build (release)"
# SWIFT_BUILD_FLAGS 透传额外参数（受限/嵌套沙箱里需要 --disable-sandbox 时用）
swift build -c release ${=SWIFT_BUILD_FLAGS:-}

APP_DIR="PasteHistory.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp ".build/release/PasteHistory" "$APP_DIR/Contents/MacOS/PasteHistory"
cp "Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
# SwiftPM 资源 bundle（许愿树素材）：Bundle.module 从 app 的 Resources 里找
if [ -d ".build/release/PasteHistory_PasteHistory.bundle" ]; then
  cp -R ".build/release/PasteHistory_PasteHistory.bundle" "$APP_DIR/Contents/Resources/"
fi

# 签名身份优先级：Apple Development（开发者证书，最正规）> 自签 PasteHistory > 现场生成自签
# 说明：TCC（辅助功能权限）按签名身份匹配。
#   - ad-hoc 没有稳定身份，按 cdhash 匹配 → 每次重建哈希都变 → 授权被判失效、反复弹窗，
#     粘贴功能在用户眼里就是「坏了」。所以 ad-hoc 不再静默兜底，默认直接失败。
#   - 自签 PasteHistory 的 designated requirement 是 certificate leaf 哈希，跨重建不变，
#     TCC 只需首次授权一次。
# 临时放行 ad-hoc：PASTEHISTORY_ALLOW_ADHOC=1 ./scripts/build_app.sh
# 指定其它身份：  PASTEHISTORY_SIGN_IDENTITY="Apple Development: xxx (TEAMID)" ./scripts/build_app.sh
SIGN_IDENTITY="${PASTEHISTORY_SIGN_IDENTITY:-}"

if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep '"Apple Development' | head -1 | sed -E 's/.*"([^"]+)".*/\1/') || true
fi

if [ -z "$SIGN_IDENTITY" ] && security find-certificate -c PasteHistory >/dev/null 2>&1; then
    SIGN_IDENTITY="PasteHistory"
fi

if [ -z "$SIGN_IDENTITY" ]; then
    echo "==> 没有稳定签名身份，创建自签证书 PasteHistory（一次性，写入登录钥匙串）"
    "$(dirname "$0")/make_signing_cert.sh" || true
    if security find-certificate -c PasteHistory >/dev/null 2>&1; then
        SIGN_IDENTITY="PasteHistory"
    fi
fi

if [ -z "$SIGN_IDENTITY" ]; then
    if [ "${PASTEHISTORY_ALLOW_ADHOC:-0}" = "1" ]; then
        codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true
        echo "==> 警告：ad-hoc 签名（PASTEHISTORY_ALLOW_ADHOC=1）——重建后辅助功能授权会失效"
        exit 0
    fi
    echo "(!) 无可用的稳定签名身份，构建中止：用 ad-hoc 会把辅助功能（TCC）授权冲掉。" >&2
    echo "    临时放行：PASTEHISTORY_ALLOW_ADHOC=1 ./scripts/build_app.sh" >&2
    exit 1
fi

codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
echo "==> 已用稳定身份签名: $SIGN_IDENTITY"

# 校验：designated requirement 里带证书哈希（自签时是 certificate root，链式证书是
# certificate leaf）才算身份稳定；只有 cdhash 说明还是 ad-hoc，重建后 TCC 授权照样失效
codesign --verify --strict "$APP_DIR"
DR=$(codesign -d -r- "$APP_DIR" 2>&1 | grep -E '^designated' || true)
echo "==> ${DR:-designated requirement 读取失败}"
case "$DR" in
    *"certificate leaf"*|*"certificate root"*) ;;
    *) echo "(!) designated requirement 不含证书哈希，重建后辅助功能授权仍会失效" >&2 ;;
esac

echo "==> 完成: $(pwd)/$APP_DIR"
