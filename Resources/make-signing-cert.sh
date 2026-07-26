#!/bin/bash
# 建一张本机自用的代码签名证书，只需跑这一次。
#
# 为什么要它：build.sh 原本用 ad-hoc 签名（codesign -s -），而 ad-hoc 签名每次重建都不一样，
# macOS 于是把每次构建都当成另一个程序 —— 钥匙串授权、以及其他按程序记的系统授权，
# 每次重建后都要重新点一遍。换成一张固定的证书，签名从此稳定，授权点一次就够。
#
# 这张证书只在本机有效，不能用来分发（那需要 Apple 的开发者证书）。
set -e

NAME="Workdesk Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "✓ 「$NAME」已经存在，不用再建"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 一张自签名证书，扩展用途标成代码签名 —— 少了 codeSigning 这项，codesign 不认它。
cat > "$TMP/openssl.cnf" <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = Workdesk Local Signing
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/openssl.cnf" 2>/dev/null

# OpenSSL 3 默认用 AES-256 + SHA-256 打包 PKCS12，而 macOS 的 security 读不了那种，
# 会报「MAC verification failed」。-legacy 换回它认得的老算法；系统自带的 LibreSSL
# 本来就只会老算法、也不认这个参数，所以两种都试一遍。
PASS=workdesk
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/bundle.p12" -passout "pass:$PASS" -name "$NAME" 2>/dev/null \
|| openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/bundle.p12" -passout "pass:$PASS" -name "$NAME" 2>/dev/null

# -T /usr/bin/codesign：让 codesign 用这把私钥时不必每次弹窗问你要密码。
security import "$TMP/bundle.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign

# 信任它用于代码签名。这一步会问一次你的登录密码。
echo "接下来要把证书标成「代码签名可信」，系统会问一次你的登录密码："
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo
if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "✓ 建好了。下次 ./build.sh 就会用它签名，签名从此稳定。"
else
    echo "✗ 证书建了但 codesign 还不认它，build.sh 会退回 ad-hoc 签名。"
    echo "  可以在「钥匙串访问」里找到「$NAME」，把「信任 → 代码签名」设为「始终信任」。"
fi
