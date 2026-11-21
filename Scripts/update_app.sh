#!/bin/bash
# Invoked only after GUI confirmation, from a private copy outside the app bundle.
set -euo pipefail
umask 077

[[ $# == 4 ]] || exit 2
APP_PID="$1"
VERSION="$2"
TARGET="$3"
RUN_DIR="$4"
[[ "$APP_PID" =~ ^[1-9][0-9]*$ ]] || exit 2
[[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || exit 2
[[ "$TARGET" == /*/ScreenCaptureAll.app && "$RUN_DIR" == /* && -d "$RUN_DIR" ]] || exit 2

exec > "$RUN_DIR/update.log" 2>&1
INSTALL_DIR="${TARGET%/*}"

finish() {
    local result=$?
    trap - EXIT
    printf '%s\n' "$result" > "$RUN_DIR/result.tmp"
    mv "$RUN_DIR/result.tmp" "$RUN_DIR/result"
    if [[ -d "$TARGET" ]]; then
        if ! open "$TARGET"; then
            echo "Could not reopen $TARGET. Open it from Applications."
        fi
    else
        # A failed rollback may leave only the installer's backup. Keep the log
        # and show its location without needing Accessibility or shell quoting.
        /usr/bin/osascript - "$RUN_DIR/update.log" <<'APPLESCRIPT' || true
on run argv
    display alert "ScreenCaptureAll update failed" message ("The app could not be reopened. Check the update log for the retained backup location:" & return & item 1 of argv) as critical
end run
APPLESCRIPT
    fi
    exit "$result"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Never stop the parent or any other app instance. Give normal termination time
# to finish; the installer independently refuses all running app instances.
echo "Waiting for ScreenCaptureAll to quit."
for ((attempt=0; attempt<30; attempt++)); do
    if ! kill -0 "$APP_PID" 2>/dev/null; then
        /bin/bash "$RUN_DIR/install.sh" --version "$VERSION" \
            --install-dir "$INSTALL_DIR" --replace --yes
        exit 0
    fi
    sleep 1
done
echo "The app did not quit within 30 seconds; nothing installed."
exit 1
