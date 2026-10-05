#!/bin/zsh
#
# 一度だけ実行するセットアップ。
# 固定の自己署名証明書を作り、それでCaptureに署名してインストールする。
# 以後は再ビルドしても画面収録などの許可を取り直す必要がなくなる。
#
set -euo pipefail

NAME="Capture Local Signing"
repository_root="${0:A:h:h}"
app_source="$repository_root/.build/Capture.app"
app_destination="/Applications/Capture.app"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then
    echo "▶ 署名証明書「$NAME」は既にあります。作成をスキップします。"
else
    echo "▶ 署名証明書「$NAME」を作成します…"
    tmp="$(mktemp -d)"
    cat > "$tmp/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $NAME
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
    openssl req -x509 -newkey rsa:2048 -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
        -days 3650 -nodes -config "$tmp/cert.cnf" >/dev/null 2>&1
    keychain="$HOME/Library/Keychains/login.keychain-db"
    # Import the private key and certificate directly (avoids PKCS#12 MAC
    # incompatibilities between modern openssl and macOS `security`).
    security import "$tmp/key.pem" -k "$keychain" -T /usr/bin/codesign -A
    security import "$tmp/cert.pem" -k "$keychain" -T /usr/bin/codesign -A
    rm -rf "$tmp"
    echo "  作成しました。"
fi

echo "▶ Captureをビルドして署名します…"
echo "  （初回は『codesignがキーを使用しようとしています』と出たら【常に許可】を押してください）"
PICTOJOT_APP_SIGN_IDENTITY="$NAME" "$repository_root/Scripts/build-app.sh" release >/dev/null

echo "▶ /Applications にインストールします…"
rm -rf "$app_destination"
cp -R "$app_source" "$app_destination"
xattr -cr "$app_destination"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_destination"

echo "▶ 画面収録の許可をリセットします（次の1回で確定）…"
tccutil reset ScreenCapture io.github.sikkimtemi.PictoJot >/dev/null 2>&1 || true

open "$app_destination"
echo ""
echo "✅ 完了しました。"
echo "   1) ⌘⇧2 を押す → 画面収録を許可"
echo "   2) Captureを一度終了して再起動"
echo "   これ以降は、アプリを更新しても再許可は不要です。"
