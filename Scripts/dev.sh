#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
APP="$ROOT/.build/capture-diagnostics/ScreenCaptureAll-Diagnostics.app"
RUNS="$ROOT/.build/capture-diagnostics/runs"
IMAGES=0
BUILD_OPTIONS=()

for option in "$@"; do
    case "$option" in
        --artifacts) IMAGES=1 ;;
        --no-build) BUILD_OPTIONS=(--no-build) ;;
        --help)
            echo "Usage: bash Scripts/dev.sh [--artifacts] [--no-build]"
            echo "Build/sign/launch the diagnostic app and stream logs. PNG evidence is opt-in."
            echo "Ctrl-C stops watching; the app stays running. Quit it from its menu before rebuilding."
            exit 0
            ;;
        *) echo "Unknown option: $option" >&2; exit 2 ;;
    esac
done

if pgrep -x ScreenCaptureAll >/dev/null; then
    echo "Quit all ScreenCaptureAll instances before starting dev mode. No process was stopped." >&2
    exit 1
fi

RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')-$(uuidgen)"
EVIDENCE="$RUNS/$RUN_ID"
mkdir -p "$EVIDENCE"
export SCREEN_CAPTURE_DIAGNOSTICS_DIR="$EVIDENCE"
export SCREEN_CAPTURE_DIAGNOSTICS_IMAGES="$IMAGES"
export SCREEN_CAPTURE_RUN_ID="$RUN_ID"

bash "$ROOT/Scripts/run_capture_diagnostics.sh" --prepare-only ${BUILD_OPTIONS[@]+"${BUILD_OPTIONS[@]}"}

LOG_PID=""
READER_PID=""
LAUNCH_PID=""
PIPE="$EVIDENCE/.log-pipe"

cleanup() {
    # Only our own watcher/reader/waiter children, never the application.
    for pid in "$LOG_PID" "$READER_PID" "$LAUNCH_PID"; do
        if [[ -n "$pid" ]]; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    done
    rm -f "$PIPE"
}
trap cleanup EXIT
trap 'echo "Stopped watching. The app was not quit. Evidence: $EVIDENCE"; exit 130' INT
trap 'exit 143' TERM

mkfifo "$PIPE"
# Launch Services gives the app its own lifecycle; it is not a child of this terminal.
# Filter out installed builds of the same subsystem by the diagnostic app's path.
# The app processImagePath is stable, while process-name filters would include installed builds.
PROCESS_PATH="$APP/Contents/MacOS/ScreenCaptureAll"
PROCESS_PATH=${PROCESS_PATH//\\/\\\\}
PROCESS_PATH=${PROCESS_PATH//\"/\\\"}
/usr/bin/log stream --level debug --style compact \
    --predicate "subsystem == \"com.oryam.ScreenCaptureAll\" AND processImagePath == \"$PROCESS_PATH\"" \
    > "$PIPE" 2> "$EVIDENCE/log-stream.stderr" &
LOG_PID=$!

# Keep printing after the local file reaches 16 MiB; don't grow it indefinitely.
LC_ALL=C awk -v output="$EVIDENCE/unified.log" -v ready="$EVIDENCE/.log-ready" '
    BEGIN { bytes = 0; limit = 16 * 1024 * 1024 }
    {
        print; fflush()
        if (!started) { print "ready" > ready; close(ready); started = 1 }
        size = length($0) + 1
        if (!limited && bytes + size <= limit) {
            print >> output; fflush(output); bytes += size
        } else if (!limited) {
            print "unified.log reached 16 MiB; live output continues, file recording stopped."
            fflush(); limited = 1
        }
    }
' < "$PIPE" &
READER_PID=$!

# Wait for log stream's initial header, rather than losing the app's startup events.
for ((attempt = 0; attempt < 50; attempt++)); do
    if ! kill -0 "$LOG_PID" 2>/dev/null || ! kill -0 "$READER_PID" 2>/dev/null; then
        echo "Log streaming failed; app not launched. See $EVIDENCE/log-stream.stderr" >&2
        exit 1
    fi
    [[ -f "$EVIDENCE/.log-ready" ]] && break
    sleep 0.1
done
if [[ ! -f "$EVIDENCE/.log-ready" ]]; then
    echo "Log stream did not become ready; app not launched. See $EVIDENCE/log-stream.stderr" >&2
    exit 1
fi

if pgrep -x ScreenCaptureAll >/dev/null; then
    echo "A ScreenCaptureAll instance started during setup; refusing another launch." >&2
    exit 1
fi
echo "Dev mode: $EVIDENCE (PNG collection: $IMAGES)"
echo "Ctrl-C stops watching only. Quit the app from its menu to finish the run."
open -W "$APP" --env "SCREEN_CAPTURE_DIAGNOSTICS_DIR=$EVIDENCE" \
    --env "SCREEN_CAPTURE_DIAGNOSTICS_IMAGES=$IMAGES" --env "SCREEN_CAPTURE_RUN_ID=$RUN_ID" &
LAUNCH_PID=$!

while kill -0 "$LAUNCH_PID" 2>/dev/null; do
    if ! kill -0 "$LOG_PID" 2>/dev/null || ! kill -0 "$READER_PID" 2>/dev/null; then
        echo "Log streaming stopped unexpectedly. App was not quit. See $EVIDENCE/log-stream.stderr" >&2
        exit 1
    fi
    sleep 0.2
done
wait "$LAUNCH_PID"
LAUNCH_PID=""
echo "App closed. Logs and evidence: $EVIDENCE"
