#!/usr/bin/env bash
# Builds Wakey from source and installs it: curl -fsSL https://raw.githubusercontent.com/nezakoo/wakey/main/install.sh | bash
set -euo pipefail

TARBALL=https://github.com/nezakoo/wakey/archive/refs/heads/main.tar.gz
APP=/Applications/Wakey.app

xcode-select -p >/dev/null 2>&1 || { echo "Needs the Xcode Command Line Tools: xcode-select --install" >&2; exit 1; }

src=$(mktemp -d)
trap 'rm -rf "$src"' EXIT
curl -fsSL "$TARBALL" | tar xz -C "$src" --strip-components=1
"$src/build.sh"

# A running session is a separate caffeinate, so it survives the restart.
pkill -x Wakey || true
rm -rf "$APP"
cp -R "$src/build/Wakey.app" "$APP"
open "$APP"
echo "Installed $APP. Wakey menu → Open at login to start it at login."
