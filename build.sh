#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Wakey.app
ICONSET=build/AppIcon.iconset
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"

swiftc -O -o "$APP/Contents/MacOS/Wakey" Sources/*.swift
cp Info.plist "$APP/Contents/"
install -m 0755 wakey.sh "$APP/Contents/Resources/wakey.sh"

swift tools/make-icon.swift build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "built $APP"
