#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
APP="$ROOT/.build/capture-diagnostics/ScreenCaptureAll-Diagnostics.app"
EVIDENCE=${SCREEN_CAPTURE_DIAGNOSTICS_DIR:-}
IDENTITY="ScreenCaptureAll Diagnostics Development"
BUILD_IDENTITY="$APP/Contents/Resources/BuildIdentity"
BUILD=1
LAUNCH=1
IMAGES=${SCREEN_CAPTURE_DIAGNOSTICS_IMAGES:-1}
RUN_ID=${SCREEN_CAPTURE_RUN_ID:-}

for option in "$@"; do
    case "$option" in
        --no-build) BUILD=0 ;;
        --prepare-only) LAUNCH=0 ;;
        --help)
            echo "Usage: SCREEN_CAPTURE_DIAGNOSTICS_DIR=<path> bash Scripts/run_capture_diagnostics.sh [--no-build] [--prepare-only]"
            echo "PNG evidence is enabled unless SCREEN_CAPTURE_DIAGNOSTICS_IMAGES=0."
            exit 0
            ;;
        *) echo "Unknown option: $option" >&2; exit 2 ;;
    esac
done

if [[ -z "$EVIDENCE" ]]; then
    echo "Set SCREEN_CAPTURE_DIAGNOSTICS_DIR to a local evidence directory." >&2
    exit 2
fi

case "$IMAGES" in
    0|1) ;;
    *) echo "SCREEN_CAPTURE_DIAGNOSTICS_IMAGES must be 0 or 1." >&2; exit 2 ;;
esac

if pgrep -x ScreenCaptureAll >/dev/null; then
    echo "Quit all ScreenCaptureAll instances before rebuilding or launching diagnostics." >&2
    exit 1
fi

if [[ "$BUILD" == 1 ]] && ! security find-identity -v -p codesigning | rg -F "\"$IDENTITY\"" >/dev/null; then
    echo "Stable signing identity missing. Run: bash Scripts/setup_capture_diagnostics_signing.sh" >&2
    exit 1
fi

if [[ "$BUILD" == 1 ]]; then
    if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
        echo "Missing app icon. Run: bash Scripts/build_app_icon.sh" >&2
        exit 1
    fi
    swift build -c debug --package-path "$ROOT"
    BIN_DIR=$(swift build -c debug --package-path "$ROOT" --show-bin-path)
    # Only generated build-provenance copies, never repository sources or run evidence.
    # Deleted source files must not survive in a later build's recorded snapshot.
    rm -rf "$BUILD_IDENTITY/source" "$BUILD_IDENTITY/scripts"
    mkdir -p "$APP/Contents/MacOS" "$BUILD_IDENTITY/source" "$BUILD_IDENTITY/scripts"
    cp "$BIN_DIR/ScreenCaptureAll" "$APP/Contents/MacOS/ScreenCaptureAll"
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ScreenCaptureAll</string>
<key>CFBundleIdentifier</key><string>com.oryam.ScreenCaptureAll.Diagnostics</string>
<key>CFBundleName</key><string>ScreenCaptureAll Diagnostics</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
    git -C "$ROOT" rev-parse HEAD > "$BUILD_IDENTITY/source-revision.txt"
    git -C "$ROOT" diff -- Sources Scripts Resources > "$BUILD_IDENTITY/source-changes.patch"
    cp "$ROOT"/Sources/*.swift "$ROOT/Package.swift" "$BUILD_IDENTITY/source/"
    cp "$ROOT"/Scripts/*.sh "$BUILD_IDENTITY/scripts/"
    cp "$ROOT"/Scripts/*.swift "$BUILD_IDENTITY/scripts/"
    date -u '+build_utc=%Y-%m-%dT%H:%M:%SZ' > "$BUILD_IDENTITY/build-info.txt"
    swift --version >> "$BUILD_IDENTITY/build-info.txt"
    # Patch output is lossy for binary artwork, so pin the exact icon bytes too.
    (cd "$ROOT" && shasum -a 256 Resources/*) >> "$BUILD_IDENTITY/build-info.txt"
    codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
elif [[ ! -x "$APP/Contents/MacOS/ScreenCaptureAll" || ! -f "$BUILD_IDENTITY/build-info.txt" ]]; then
    echo "No diagnostic build with recorded provenance. Run without --no-build first." >&2
    exit 1
fi

# Verify both the sealed bundle and the expected identity, including when reusing a build.
codesign --verify --strict -R "=identifier \"com.oryam.ScreenCaptureAll.Diagnostics\" and certificate leaf[subject.CN] = \"$IDENTITY\"" "$APP"
mkdir -p "$EVIDENCE"
cp -R "$BUILD_IDENTITY/." "$EVIDENCE/"
codesign -d -r- "$APP" 2> "$EVIDENCE/signing-requirement.txt"
shasum -a 256 "$APP/Contents/MacOS/ScreenCaptureAll" > "$EVIDENCE/binary-sha256.txt"
RUN_ID=${RUN_ID:-$(uuidgen)}
printf 'run_id=%s\nimages=%s\napp=%s\n' "$RUN_ID" "$IMAGES" "$APP" > "$EVIDENCE/run-info.txt"

if [[ "$LAUNCH" == 1 ]]; then
    open "$APP" --env "SCREEN_CAPTURE_DIAGNOSTICS_DIR=$EVIDENCE" \
        --env "SCREEN_CAPTURE_DIAGNOSTICS_IMAGES=$IMAGES" --env "SCREEN_CAPTURE_RUN_ID=$RUN_ID"
    echo "Diagnostics app launched. Evidence: $EVIDENCE (PNG collection: $IMAGES)"
else
    echo "Diagnostics app prepared, not launched. Evidence: $EVIDENCE"
fi
