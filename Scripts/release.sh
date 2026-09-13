#!/bin/zsh
# Builds, signs (Developer ID), notarizes and staples a Release zip for the Homebrew cask.
# Usage: Scripts/release.sh [--publish]
#   --publish  create GitHub release on ljack/macos-md-reader, bump Casks/md-reader.rb, mirror to ljack/homebrew-tap
# One-time: xcrun notarytool store-credentials "$NOTARY_PROFILE" --apple-id <id> --team-id 25C9H9N953 --password <app-specific>
set -euo pipefail
cd "$(dirname "$0")/.."
NOTARY_PROFILE="${NOTARY_PROFILE:-md-reader-notary}"
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || { echo "working tree dirty; releases must come from a commit"; exit 1 }
COMMIT=$(git rev-parse HEAD)
VERSION=$(sed -n 's/^        CFBundleShortVersionString: "\(.*\)"/\1/p' project.yml)
[[ -n "$VERSION" ]] || { echo "version not found in project.yml"; exit 1 }
./Scripts/build.sh >/dev/null
APP="build/MD Reader.app"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -1
codesign -dvv "$APP" 2>&1 | grep -E "^Authority=Developer ID" | head -1 || { echo "not Developer ID signed"; exit 1 }

ZIP="build/MD-Reader-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
if [[ "${SKIP_NOTARIZE:-}" != "1" ]]; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  spctl -a -vv -t exec "$APP" 2>&1 | tail -2
fi
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
echo "version: $VERSION"
echo "zip:     $ZIP"
echo "sha256:  $SHA"

if [[ "${1:-}" == "--publish" ]]; then
  REPO=ljack/macos-md-reader
  TAP=ljack/homebrew-tap
  TAG="v$VERSION"
  NOTES="Built from commit $COMMIT on $(date -u +%Y-%m-%d).

Provenance: About MD Reader shows the commit; \`Copy Build Info\` copies it.

\`\`\`
sha256  $SHA  MD-Reader-$VERSION.zip
\`\`\`"
  gh release create "$TAG" "$ZIP" --repo "$REPO" --target "$COMMIT" --title "MD Reader $VERSION" --notes "$NOTES" 2>/dev/null \
    || gh release upload "$TAG" "$ZIP" --repo "$REPO" --clobber
  sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" Casks/md-reader.rb
  git add Casks/md-reader.rb && git commit -qm "Release $VERSION" && git push -q
  TMP=$(mktemp -d)
  gh repo clone "$TAP" "$TMP/tap" -- -q
  mkdir -p "$TMP/tap/Casks" && cp Casks/md-reader.rb "$TMP/tap/Casks/md-reader.rb"
  git -C "$TMP/tap" add -A && git -C "$TMP/tap" commit -qm "md-reader $VERSION" && git -C "$TMP/tap" push -q
  rm -rf "$TMP"
  echo "published: brew install --cask $TAP/md-reader"
fi
