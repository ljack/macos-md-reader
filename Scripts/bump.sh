#!/bin/zsh
# Bumps CFBundleShortVersionString in project.yml and commits. Usage: Scripts/bump.sh 0.2.0
set -euo pipefail
cd "$(dirname "$0")/.."
V="${1:?usage: bump.sh X.Y.Z}"
[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "not semver: $V"; exit 1 }
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || { echo "working tree dirty; commit first"; exit 1 }
sed -i '' "s/^        CFBundleShortVersionString: \".*\"/        CFBundleShortVersionString: \"$V\"/" project.yml
git add project.yml
git commit -qm "Bump version to $V"
echo "bumped to $V (commit $(git rev-parse --short HEAD)); next: make release"
