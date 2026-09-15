#!/bin/zsh
# Writes git provenance into the built app's Info.plist (runs as an Xcode post-build phase).
# Keys: GitCommit (short sha, "-dirty" suffix if uncommitted changes), GitBranch, BuildDate (UTC),
#       CFBundleVersion = commit count on HEAD (monotonic build number).
set -euo pipefail
PLIST="$1"
cd "$(dirname "$0")/.."
PB=/usr/libexec/PlistBuddy
if git rev-parse --git-dir >/dev/null 2>&1; then
  SHA=$(git rev-parse --short=12 HEAD)
  COUNT=$(git rev-list --count HEAD)
  BRANCH=$(git rev-parse --abbrev-ref HEAD)
  # Dirty if tracked files changed anywhere, or if untracked files sit inside the directories
  # XcodeGen compiles from (they end up in the binary without being in the commit).
  DIRTY=""
  if [[ -n "$(git status --porcelain --untracked-files=no)" ]] \
     || [[ -n "$(git status --porcelain --untracked-files=all -- MDReader MDReaderTests Scripts | grep '^??' || true)" ]]; then
    DIRTY="-dirty"
  fi
else
  SHA=unknown; COUNT=0; BRANCH=unknown; DIRTY=""
fi
DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
set_key() { $PB -c "Set :$1 $2" "$PLIST" 2>/dev/null || $PB -c "Add :$1 string $2" "$PLIST"; }
set_key CFBundleVersion "$COUNT"
set_key GitCommit "$SHA$DIRTY"
set_key GitBranch "$BRANCH"
set_key BuildDate "$DATE"
echo "stamped $SHA$DIRTY ($COUNT) $BRANCH $DATE"
