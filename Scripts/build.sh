#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f MDReader/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json ]] || swift Scripts/gen-icon.swift
xcodegen generate
xcodebuild -scheme MDReader -configuration Release -derivedDataPath build/DerivedData build | tail -3
rm -rf "build/MD Reader.app"
ditto "build/DerivedData/Build/Products/Release/MD Reader.app" "build/MD Reader.app"
rm -rf "build/DerivedData/Build/Products/Release/MD Reader.app"
echo "→ build/MD Reader.app"
if [[ "${1:-}" == "--install" ]]; then
  rm -rf "/Applications/MD Reader.app"
  ditto "build/MD Reader.app" "/Applications/MD Reader.app"
  echo "→ installed to /Applications/MD Reader.app"
fi
