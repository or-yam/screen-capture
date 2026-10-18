#!/usr/bin/env bash
# Isolated build tools; no global pip installs or unpinned package upgrades.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PYTHON=${PYTHON:-python3}
TOOLS="$ROOT/.build/dmg-tools"

"$PYTHON" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else "DMG tooling requires Python 3.10+; set PYTHON to a suitable interpreter.")'
mkdir -p "$ROOT/.build"
"$PYTHON" -m venv "$TOOLS"
"$TOOLS/bin/python" -m pip --disable-pip-version-check install \
  --require-hashes --only-binary=:all: -r "$ROOT/Scripts/dmg-requirements.txt"
"$TOOLS/bin/python" -m pip check
shasum -a 256 "$ROOT/Scripts/dmg-requirements.txt" | awk '{print $1}' > "$TOOLS/.requirements-sha256"
echo "DMG tooling ready in $TOOLS"
