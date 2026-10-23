#!/bin/zsh
# 生成稳定的本地代码签名身份（自签证书 CN=PasteHistory），一次性写入登录钥匙串。
#
# 为什么需要：TCC（辅助功能权限）按签名身份匹配。ad-hoc 签名每次重建 cdhash 都变，
# 系统判定授权失效 → 反复弹窗、粘贴像坏了一样。换成一个固定证书后，每次重建
# designated requirement 里的 certificate leaf 不变，只需首次授权一次。
#
# 用法：
#   ./scripts/make_signing_cert.sh              # 幂等：已有证书直接跳过
#   ./scripts/make_signing_cert.sh --force      # 删掉旧的自签证书重建
#   ./scripts/make_signing_cert.sh --trust      # 额外把证书标记为「仅代码签名」受信任
#
# 可选信任（默认不做）：自签证书不信任也能 codesign 成功、TCC 也认它；
# 标记受信任只是让 `security find-identity -p codesigning` 能列出来、spctl 少抱怨。
set -euo pipefail

CN="PasteHistory"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
P12_PASS="pastehistory"   # 只为过 OpenSSL 3 → keychain 的口令校验，用完即弃
TRUST=0

for arg in "$@"; do
    case "$arg" in
        --force)  security delete-identity -c "$CN" "$KEYCHAIN" >/dev/null 2>&1 || true ;;
        --trust)  TRUST=1 ;;
        *) echo "未知参数: $arg（支持 --force / --trust）" >&2; exit 2 ;;
    esac
done

if security find-certificate -c "$CN" >/dev/null 2>&1; then
    echo "==> 已存在自签证书 $CN，跳过创建（重建用 --force）"
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "==> 生成自签证书 $CN（RSA 2048，有效期 10 年，仅 digitalSignature + codeSigning）"
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$CN/O=PasteHistory Local/C=CN" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

# macOS 的 `security import` 不认 OpenSSL 3 默认的 PBES2/AES p12，会报
# "MAC verification failed"；必须退到 SHA1 MAC + 3DES 加密，且口令不能为空。
# LibreSSL（系统 /usr/bin/openssl）不认 -macalg，走不带参数的兜底分支。
echo "==> 打包 p12（OpenSSL 3 兼容参数）"
if ! openssl pkcs12 -export -macalg sha1 \
        -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES \
        -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
        -out "$WORK/id.p12" -passout "pass:$P12_PASS" >/dev/null 2>&1; then
    openssl pkcs12 -export \
        -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
        -out "$WORK/id.p12" -passout "pass:$P12_PASS" >/dev/null 2>&1
fi

echo "==> 导入登录钥匙串（-A：允许 codesign 直接取私钥，不弹「允许访问钥匙串」）"
security import "$WORK/id.p12" -k "$KEYCHAIN" -P "$P12_PASS" \
    -T /usr/bin/codesign -A >/dev/null

# 自检：真签一个临时二进制，确认身份可用且不弹授权框
cp /bin/echo "$WORK/probe"
if codesign --force --sign "$CN" "$WORK/probe" >/dev/null 2>&1; then
    echo "==> 自检通过：codesign 可用身份 $CN"
else
    echo "(!) 自检失败：证书已导入但 codesign 无法使用，请检查钥匙串访问权限" >&2
    exit 1
fi

if [ "$TRUST" = "1" ]; then
    echo "==> 标记为受信任（仅代码签名用途，可能需要输入登录密码）"
    security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem" \
        || echo "(!) 信任设置失败，可忽略——不影响 codesign 与 TCC"
fi

echo "==> 完成。后续 ./scripts/build_app.sh 会自动使用该身份，无需重复创建"
