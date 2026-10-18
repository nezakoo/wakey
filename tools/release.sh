#!/usr/bin/env bash
# Cuts a release from a clean main: tools/release.sh 1.2.0
# Tags vX.Y.Z, uploads the source tarball install.sh and the formula download, then pins the formula to it.
set -euo pipefail
cd "$(dirname "$0")/.."

v=${1:?usage: tools/release.sh X.Y.Z}
[[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Not X.Y.Z: $v" >&2; exit 1; }
[[ "$(git branch --show-current)" == main ]] || { echo "Release from main" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Working tree not clean" >&2; exit 1; }
git pull -q --ff-only
tests/engine-test.sh

build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $v" -c "Set :CFBundleVersion $(( build + 1 ))" Info.plist
git commit -qam "Wakey $v"
git tag -a "v$v" -m "Wakey $v"

out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
# Formula/ is export-ignored: it holds this tarball's checksum, so it cannot be inside it.
git archive --prefix="wakey-$v/" -o "$out/wakey.tar.gz" "v$v"
sha=$(shasum -a 256 "$out/wakey.tar.gz" | cut -d' ' -f1)
git push -q origin main "v$v"
gh release create "v$v" "$out/wakey.tar.gz" --title "Wakey $v" --generate-notes

sed -i '' -e "s#^  url .*#  url \"https://github.com/nezakoo/wakey/releases/download/v$v/wakey.tar.gz\"#" \
          -e "s#^  version .*#  version \"$v\"#" -e "s#^  sha256 .*#  sha256 \"$sha\"#" Formula/wakey.rb
git commit -qam "Formula: wakey $v"
git push -q origin main
echo "Released v$v"
