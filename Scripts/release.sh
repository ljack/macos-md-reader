#!/bin/zsh
# Builds a Release zip for the Homebrew cask and prints its sha256.
# Usage: Scripts/release.sh [--publish]   (publish = create GitHub release on ljack/homebrew-tap and bump cask)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(sed -n 's/^        CFBundleShortVersionString: "\(.*\)"/\1/p' project.yml)
[[ -n "$VERSION" ]] || { echo "version not found in project.yml"; exit 1 }
./Scripts/build.sh >/dev/null
ZIP="build/MD-Reader-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "build/MD Reader.app" "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
echo "version: $VERSION"
echo "zip:     $ZIP"
echo "sha256:  $SHA"

if [[ "${1:-}" == "--publish" ]]; then
  TAP=ljack/homebrew-tap
  TAG="md-reader-v$VERSION"
  gh release create "$TAG" "$ZIP" --repo "$TAP" --title "MD Reader $VERSION" --notes "MD Reader $VERSION" 2>/dev/null \
    || gh release upload "$TAG" "$ZIP" --repo "$TAP" --clobber
  TMP=$(mktemp -d)
  gh repo clone "$TAP" "$TMP/tap" -- -q
  sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$TMP/tap/Casks/md-reader.rb"
  git -C "$TMP/tap" commit -qam "md-reader $VERSION" && git -C "$TMP/tap" push -q
  rm -rf "$TMP"
  echo "published: brew install --cask $TAP/md-reader"
fi
