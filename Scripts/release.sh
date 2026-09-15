#!/bin/zsh
# Builds, signs (Developer ID), notarizes and staples a Release zip for the Homebrew cask.
# Usage: Scripts/release.sh [--publish]
#   --publish  create GitHub release on ljack/macos-md-reader, bump Casks/md-reader.rb, mirror to ljack/homebrew-tap
# One-time: xcrun notarytool store-credentials "$NOTARY_PROFILE" --apple-id <id> --team-id 25C9H9N953 --password <app-specific>
set -euo pipefail
cd "$(dirname "$0")/.."
NOTARY_PROFILE="${NOTARY_PROFILE:-md-reader-notary}"
PUBLISH=0; [[ "${1:-}" == "--publish" ]] && PUBLISH=1
# Every build input must be committed: tracked changes, untracked files, and ignored files inside
# the source/resource directories XcodeGen scans (they would compile in without a -dirty stamp).
[[ -z "$(git status --porcelain --untracked-files=all)" ]] || { echo "working tree dirty or has untracked files; releases must come from a commit"; exit 1 }
STRAY=$(git ls-files --others --ignored --exclude-standard MDReader MDReaderTests Scripts | grep -v -e '/\.DS_Store$' -e '^MDReader/Info.plist$' || true)
[[ -z "$STRAY" ]] || { echo "ignored files inside build inputs would be built without provenance:"; echo "$STRAY"; exit 1 }
if (( PUBLISH )); then
  [[ "${SKIP_NOTARIZE:-}" != "1" ]] || { echo "SKIP_NOTARIZE=1 is not allowed with --publish"; exit 1 }
  make ci
fi
COMMIT=$(git rev-parse HEAD)
VERSION=$(sed -n 's/^        CFBundleShortVersionString: "\(.*\)"/\1/p' project.yml)
[[ -n "$VERSION" ]] || { echo "version not found in project.yml"; exit 1 }
./Scripts/build.sh >/dev/null
APP="build/MD Reader.app"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -1
codesign -dvv "$APP" 2>&1 | grep -E "^Authority=Developer ID" | head -1 || { echo "not Developer ID signed"; exit 1 }

STAMP=$(/usr/libexec/PlistBuddy -c "Print :GitCommit" "$APP/Contents/Info.plist" 2>/dev/null || true)
[[ "$STAMP" == "$(git rev-parse --short=12 HEAD)" ]] || { echo "provenance stamp '$STAMP' does not match HEAD; refusing to release"; exit 1 }
echo "provenance: $STAMP"

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

if (( PUBLISH )); then
  REPO=ljack/macos-md-reader
  TAP=ljack/homebrew-tap
  TAG="v$VERSION"
  NOTES="Built from commit $COMMIT on $(date -u +%Y-%m-%d).

Provenance: About MD Reader shows the commit; \`Copy Build Info\` copies it.

\`\`\`
sha256  $SHA  MD-Reader-$VERSION.zip
\`\`\`"
  # Fail closed: a tag that already exists means this version was published from some commit;
  # never replace its asset. Bump the version instead.
  if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 || git ls-remote --tags origin "refs/tags/$TAG" | grep -q .; then
    echo "release $TAG already exists; bump the version (make bump V=...) instead of re-publishing"; exit 1
  fi
  git push -q --no-verify origin HEAD  # --target must exist on GitHub
  gh release create "$TAG" "$ZIP" --repo "$REPO" --target "$COMMIT" --title "MD Reader $VERSION" --notes "$NOTES"
  sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" Casks/md-reader.rb
  git add Casks/md-reader.rb && git commit -qm "Release $VERSION" && git push -q --no-verify
  TMP=$(mktemp -d)
  gh repo clone "$TAP" "$TMP/tap" -- -q
  mkdir -p "$TMP/tap/Casks" && cp Casks/md-reader.rb "$TMP/tap/Casks/md-reader.rb"
  git -C "$TMP/tap" add -A && git -C "$TMP/tap" commit -qm "md-reader $VERSION" && git -C "$TMP/tap" push -q
  rm -rf "$TMP"
  echo "published: brew install --cask $TAP/md-reader"
fi
