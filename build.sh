#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_DIR="${IOS_SDK_DIR:-/tmp/theos-sdks/iPhoneOS9.3.sdk}"
TOOLCHAIN_BIN="${IOS_TOOLCHAIN_BIN:-/tmp/ios-toolchain/linux/iphone/bin}"
LDID_BIN="${LDID_BIN:-/tmp/ios-tools/ldid_linux_x86_64}"

if [[ ! -d "$SDK_DIR" ]]; then
    echo "Fetching iPhoneOS9.3.sdk..."
    git clone --depth=1 --filter=blob:none --sparse https://github.com/theos/sdks.git /tmp/theos-sdks
    git -C /tmp/theos-sdks sparse-checkout set iPhoneOS9.3.sdk
fi

# Ensure umbrella re-export stub exists if missing from sparse checkout
if [[ ! -f "$SDK_DIR/usr/lib/system/liblaunch.tbd" ]]; then
    cat << 'EOF' > "$SDK_DIR/usr/lib/system/liblaunch.tbd"
---
archs:                 [ armv7, armv7s, arm64 ]
platform:              ios
install-name:          /usr/lib/system/liblaunch.dylib
current-version:       765.50.8
compatibility-version: 1
exports:
  - archs:              [ armv7, armv7s, arm64 ]
    symbols:            [ __spawn_via_launchd ]
...
EOF
fi

if [[ ! -x "$TOOLCHAIN_BIN/clang" ]]; then
    echo "Fetching Linux iOS toolchain..."
    mkdir -p /tmp/ios-tools /tmp/ios-toolchain
    gh release download -R L1ghtmann/llvm-project --pattern "iOSToolchain-x86_64.tar.xz" --dir /tmp/ios-tools --clobber
    tar -xJf /tmp/ios-tools/iOSToolchain-x86_64.tar.xz -C /tmp/ios-toolchain
fi

if [[ ! -x "$LDID_BIN" ]]; then
    if [[ -x "$TOOLCHAIN_BIN/ldid" ]]; then
        LDID_BIN="$TOOLCHAIN_BIN/ldid"
    else
        mkdir -p /tmp/ios-tools
        gh release download v2.1.5-procursus7 -R ProcursusTeam/ldid --pattern "ldid_linux_x86_64" --dir /tmp/ios-tools --clobber
        chmod +x /tmp/ios-tools/ldid_linux_x86_64
        LDID_BIN="/tmp/ios-tools/ldid_linux_x86_64"
    fi
fi

APP_STAGE="$ROOT_DIR/build/Payload/PDFNotes.app"
rm -rf "$ROOT_DIR/build/Payload" "$ROOT_DIR/build/PDFNotes.ipa"
mkdir -p "$APP_STAGE"

cp -R "$ROOT_DIR/Resources/"* "$APP_STAGE/"

echo "Compiling PDFNotes (armv7, iOS 9.0 min / 9.3 SDK)..."
"$TOOLCHAIN_BIN/clang" \
    -target armv7-apple-ios9.0 \
    -isysroot "$SDK_DIR" \
    -O2 \
    -fobjc-arc \
    -Wall -Wextra -Wno-unused-parameter \
    "$ROOT_DIR"/src/*.m \
    -framework UIKit \
    -framework Foundation \
    -framework CoreGraphics \
    -framework QuartzCore \
    -o "$APP_STAGE/PDFNotes"

echo "Signing PDFNotes.app with ldid..."
"$LDID_BIN" -S "$APP_STAGE/PDFNotes"

echo "Packaging PDFNotes.ipa..."
(
    cd "$ROOT_DIR/build"
    zip -qr -9 "$ROOT_DIR/build/PDFNotes.ipa" Payload
)

cp "$ROOT_DIR/build/PDFNotes.ipa" "$ROOT_DIR/PDFNotes.ipa"
cp "$ROOT_DIR/build/PDFNotes.ipa" "/home/antigravity/PDFNotes-v3.0-iOS9.ipa"

echo "Built $ROOT_DIR/PDFNotes.ipa ($(stat -c%s "$ROOT_DIR/PDFNotes.ipa") bytes)"
