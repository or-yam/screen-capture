#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUTPUT="$ROOT/.build/app-icon"
mkdir -p "$ROOT/Resources" "$OUTPUT"
swiftc "$ROOT/Sources/BrandMark.swift" "$ROOT/Scripts/generate_app_icon.swift" -o "$OUTPUT/generate-app-icon"
"$OUTPUT/generate-app-icon" "$OUTPUT"
for NAME in AppIcon AppIcon-Dark; do
  iconutil -c icns "$OUTPUT/$NAME.iconset" -o "$ROOT/Resources/$NAME.icns"
done
echo "Generated light/dark icons in Resources; previews in .build/app-icon"
