#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUTPUT="$ROOT/.build/dmg-background"
# Kept in step with the default in Scripts/package_app.sh, so the window can say
# what the build actually requires.
MACOS_MIN_VERSION=${MACOS_MIN_VERSION:-26.0}

mkdir -p "$ROOT/Resources/dmg" "$OUTPUT"
swiftc "$ROOT/Sources/BrandMark.swift" "$ROOT/Scripts/generate_dmg_background.swift" \
  -o "$OUTPUT/generate-dmg-background"
"$OUTPUT/generate-dmg-background" "$ROOT/Resources/dmg" "$OUTPUT" \
  "Screen Capture All" "Requires macOS $MACOS_MIN_VERSION or later"

echo "Wrote Resources/dmg/background.png and Resources/dmg/background@2x.png"
echo "Layout check: $OUTPUT/background-preview.png (dashed outlines mark the icon slots)"
