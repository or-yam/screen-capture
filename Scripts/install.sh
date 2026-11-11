#!/bin/bash
# Downloaded releases replace this default with their own version at packaging.
set +x
set -euo pipefail
umask 077

DEFAULT_VERSION="latest"
VERSION="$DEFAULT_VERSION"
REPOSITORY="or-yam/screen-capture"
APP_NAME="ScreenCaptureAll"
BUNDLE_ID="com.oryam.ScreenCaptureAll"
INSTALL_DIR="/Applications"
REPLACE=0
ASSUME_YES=0
VERIFY_ONLY=0
WORK_DIR=""
INSTALL_STAGE=""
LOCK_DIR=""
COMPLETE=0
NEW_INSTALLED=0

fail() { echo "ERROR: $*" >&2; exit 1; }
usage() {
  cat <<'USAGE'
Install ScreenCaptureAll from its official GitHub release ZIP.

Usage: bash install.sh [options]
  --version VERSION     Install a specific version, e.g. 1.0.3 (or latest).
  --install-dir PATH    Destination folder (default: /Applications).
  --replace             Explicitly allow replacing an existing ScreenCaptureAll.
  --yes                 Accept the unnotarized-software notice without a prompt.
  --verify-only         Download and verify; do not install or launch anything.
  --help                Show this help.

Private repository: set GH_TOKEN (Contents: read), or sign in with gh auth login.
The app is ad-hoc signed and unnotarized. No macOS security settings are changed.
USAGE
}

cleanup() {
  local result=$?
  trap - EXIT
  if [[ -n "$INSTALL_STAGE" && -d "$INSTALL_STAGE" ]]; then
    if [[ "$COMPLETE" != 1 ]]; then
      if [[ -d "$INSTALL_STAGE/previous.app" ]]; then
        if [[ -e "$TARGET" ]]; then
          mv "$TARGET" "$INSTALL_STAGE/failed.app" || result=1
        fi
        if [[ ! -e "$TARGET" ]] && mv "$INSTALL_STAGE/previous.app" "$TARGET"; then
          echo "Restored the previous app." >&2
        else
          echo "Could not restore the previous app. Backup kept at: $INSTALL_STAGE" >&2
          INSTALL_STAGE=""
          result=1
        fi
      elif [[ "$NEW_INSTALLED" == 1 ]]; then
        mv "$TARGET" "$INSTALL_STAGE/failed.app" || result=1
      fi
    fi
    [[ -z "$INSTALL_STAGE" ]] || rm -rf "$INSTALL_STAGE"
  fi
  [[ -z "$LOCK_DIR" ]] || rmdir "$LOCK_DIR" || result=1
  [[ -z "$WORK_DIR" ]] || rm -rf "$WORK_DIR"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version|--install-dir)
      [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || fail "$1 needs a value"
      if [[ "$1" == --version ]]; then VERSION="${2#v}"; else INSTALL_DIR="$2"; fi
      shift 2 ;;
    --replace) REPLACE=1; shift ;;
    --yes) ASSUME_YES=1; shift ;;
    --verify-only) VERIFY_ONLY=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) fail "Unknown option: $1 (see --help)" ;;
  esac
done
[[ "$VERSION" == latest || "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || fail "Invalid release version"
[[ "$INSTALL_DIR" == /* && "$INSTALL_DIR" != *$'\n'* ]] || fail "--install-dir must be an absolute path"
[[ "$(uname -s)" == Darwin ]] || fail "macOS is required"
[[ "$EUID" != 0 ]] || fail "Run as your normal user, without sudo"
OS_VERSION=$(sw_vers -productVersion)
[[ "${OS_VERSION%%.*}" -ge 26 ]] || fail "macOS 26 or newer is required"
ARCH=$(uname -m)
[[ "$ARCH" == arm64 || "$ARCH" == x86_64 ]] || fail "Unsupported architecture: $ARCH"

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ScreenCaptureAll-download.XXXXXX")
AUTH_HEADERS="$WORK_DIR/headers"
: > "$AUTH_HEADERS"
TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -z "$TOKEN" ]] && command -v gh >/dev/null 2>&1; then
  TOKEN=$(gh auth token --hostname github.com 2>/dev/null) || TOKEN=""
fi
if [[ -n "$TOKEN" ]]; then
  [[ "$TOKEN" =~ ^[A-Za-z0-9_]+$ ]] || fail "Invalid GitHub token format"
  # Keep the token out of curl's command-line arguments and error output.
  printf 'Authorization: Bearer %s\n' "$TOKEN" > "$AUTH_HEADERS"
fi
unset TOKEN

download() {
  local url="$1" output="$2" accept="$3"
  curl --disable --fail --silent --show-error --location \
    --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --connect-timeout 15 --max-time 300 --retry 2 \
    --header "@$AUTH_HEADERS" --header "Accept: $accept" \
    --header 'X-GitHub-Api-Version: 2022-11-28' \
    --output "$output" "$url" ||
    fail "GitHub download failed. Check the release version and connection. For private releases, use GH_TOKEN or gh auth login with repository access."
}
json() { plutil -extract "$1" raw -o - "$WORK_DIR/release.json"; }
RELEASE_PATH="tags/v$VERSION"
[[ "$VERSION" != latest ]] || RELEASE_PATH=latest
download "https://api.github.com/repos/$REPOSITORY/releases/$RELEASE_PATH" "$WORK_DIR/release.json" application/vnd.github+json
TAG=$(json tag_name) || fail "Invalid GitHub release metadata"
[[ "$TAG" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || fail "Unexpected release tag"
[[ "$VERSION" == latest || "$TAG" == "v$VERSION" ]] || fail "GitHub returned a different release"
VERSION="${TAG#v}"
ZIP_NAME="$APP_NAME-$VERSION-universal.zip"
SUM_NAME="$APP_NAME-$VERSION-universal-SHA256SUMS.txt"
ZIP_ID=""
SUM_ID=""
ASSET_COUNT=$(json assets) || fail "Release has no assets"
[[ "$ASSET_COUNT" =~ ^[0-9]+$ && "$ASSET_COUNT" -le 100 ]] || fail "Invalid release asset list"
for ((index=0; index<ASSET_COUNT; index++)); do
  name=$(json "assets.$index.name") || fail "Invalid release asset"
  if [[ "$name" == "$ZIP_NAME" ]]; then
    [[ -z "$ZIP_ID" ]] || fail "Duplicate ZIP asset"
    ZIP_ID=$(json "assets.$index.id")
  elif [[ "$name" == "$SUM_NAME" ]]; then
    [[ -z "$SUM_ID" ]] || fail "Duplicate checksum asset"
    SUM_ID=$(json "assets.$index.id")
  fi
done
[[ "$ZIP_ID" =~ ^[0-9]+$ && "$SUM_ID" =~ ^[0-9]+$ ]] || fail "Release is missing its universal ZIP or checksums"
echo "Downloading ScreenCaptureAll $VERSION from $REPOSITORY."
download "https://api.github.com/repos/$REPOSITORY/releases/assets/$SUM_ID" "$WORK_DIR/checksums.txt" application/octet-stream
EXPECTED_HASH=$(awk -v name="$ZIP_NAME" '$2 == name && NF == 2 { print $1 }' "$WORK_DIR/checksums.txt")
[[ "$EXPECTED_HASH" =~ ^[0-9a-f]{64}$ ]] || fail "Missing, duplicate, or invalid ZIP checksum"
download "https://api.github.com/repos/$REPOSITORY/releases/assets/$ZIP_ID" "$WORK_DIR/app.zip" application/octet-stream
ACTUAL_HASH=$(shasum -a 256 "$WORK_DIR/app.zip" | awk '{print $1}')
[[ "$ACTUAL_HASH" == "$EXPECTED_HASH" ]] || fail "ZIP checksum mismatch; nothing installed"
echo "SHA-256 verified: $ACTUAL_HASH"

# This app currently ships no symlinks. Refuse traversal/links before extracting,
# rather than letting an unexpected archive write outside the staging directory.
unzip -Z1 "$WORK_DIR/app.zip" > "$WORK_DIR/members" || fail "Invalid ZIP"
awk '
  index($0, "ScreenCaptureAll.app/") != 1 || /(^|\/)\.\.(\/|$)/ || /\\/ { bad=1 }
  END { exit (NR == 0 || bad) }
' "$WORK_DIR/members" || fail "ZIP contains unexpected paths"
unzip -Z -l "$WORK_DIR/app.zip" > "$WORK_DIR/modes" || fail "Cannot inspect ZIP entries"
if awk '$1 ~ /^l/ { found=1 } END { exit !found }' "$WORK_DIR/modes"; then
  fail "ZIP contains symbolic links"
fi
mkdir "$WORK_DIR/unpacked"
ditto -x -k "$WORK_DIR/app.zip" "$WORK_DIR/unpacked" || fail "Cannot extract ZIP"
APP="$WORK_DIR/unpacked/$APP_NAME.app"
INFO="$APP/Contents/Info.plist"
[[ -f "$INFO" && -x "$APP/Contents/MacOS/$APP_NAME" ]] || fail "Incomplete app bundle"
[[ "$(plutil -extract CFBundleIdentifier raw "$INFO")" == "$BUNDLE_ID" ]] || fail "Unexpected app identity"
[[ "$(plutil -extract CFBundleExecutable raw "$INFO")" == "$APP_NAME" ]] || fail "Unexpected executable"
[[ "$(plutil -extract CFBundleShortVersionString raw "$INFO")" == "$VERSION" ]] || fail "App version differs from release"
MIN_VERSION=$(plutil -extract LSMinimumSystemVersion raw "$INFO")
[[ "$MIN_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || fail "Invalid minimum macOS version"
awk -v have="$OS_VERSION" -v need="$MIN_VERSION" 'BEGIN {
  split(have,h,"."); split(need,n,".");
  for (i=1;i<=3;i++) { if (h[i]+0 > n[i]+0) exit 0; if (h[i]+0 < n[i]+0) exit 1 }
}' || fail "This app requires macOS $MIN_VERSION or newer"
BINARY_TYPE=$(file -b "$APP/Contents/MacOS/$APP_NAME")
[[ "$BINARY_TYPE" == *Mach-O* && "$BINARY_TYPE" == *"$ARCH"* ]] || fail "App does not support $ARCH"
codesign --verify --deep --strict "$APP" || fail "App signature is invalid"
check_quarantine() {
  xattr -lr "$1" > "$WORK_DIR/attributes" || fail "Cannot inspect app attributes"
  if grep -q 'com.apple.quarantine:' "$WORK_DIR/attributes"; then
    fail "App unexpectedly has quarantine metadata; nothing installed. No attributes were removed."
  fi
}
check_quarantine "$APP"
echo "Verified app identity, version, architecture, and signature integrity."
if [[ "$VERIFY_ONLY" == 1 ]]; then
  echo "Verification complete. Nothing installed or launched. This is not Apple notarization."
  exit 0
fi

TARGET="$INSTALL_DIR/$APP_NAME.app"
check_destination() {
  [[ ! -L "$TARGET" ]] || fail "Destination app is a symlink; nothing replaced"
  if [[ -e "$TARGET" ]]; then
    [[ "$REPLACE" == 1 ]] || fail "An app already exists at $TARGET. Quit it and rerun with --replace."
    [[ -d "$TARGET" && "$(plutil -extract CFBundleIdentifier raw "$TARGET/Contents/Info.plist" 2>/dev/null)" == "$BUNDLE_ID" ]] ||
      fail "Existing destination is not the expected app; nothing replaced"
  fi
  if pgrep -x "$APP_NAME" >/dev/null; then
    fail "ScreenCaptureAll is running. Quit it from its menu and rerun; no processes were stopped."
  fi
}
check_destination
cat <<NOTICE

Install ScreenCaptureAll $VERSION to $TARGET
This release is ad-hoc signed and NOT notarized by Apple.
Terminal downloading normally avoids the browser's quarantine-based launch block.
Checksums and signature integrity do not establish an Apple-verified publisher.
Continue only if you trust this project. No security settings will be changed.
NOTICE
if [[ "$ASSUME_YES" != 1 ]]; then
  [[ -t 0 ]] || fail "Interactive confirmation required (or explicitly use --yes)"
  read -r -p "Install this unnotarized app? [y/N] " answer
  [[ "$answer" == y || "$answer" == Y || "$answer" == yes ]] || fail "Installation canceled"
fi
mkdir -p "$INSTALL_DIR" || fail "Cannot create destination folder"
[[ -w "$INSTALL_DIR" ]] || fail "Destination is not writable. Use --install-dir \"\$HOME/Applications\" if needed; keep the same path for later updates."
# Acquire the lock only after successful mkdir, so cleanup never removes a
# different installer's lock. Staging/backup share the target filesystem.
if mkdir "$INSTALL_DIR/.ScreenCaptureAll.install.lock" 2>/dev/null; then
  LOCK_DIR="$INSTALL_DIR/.ScreenCaptureAll.install.lock"
else
  fail "Another installation is running, or a stale .ScreenCaptureAll.install.lock remains in $INSTALL_DIR"
fi
INSTALL_STAGE=$(mktemp -d "$INSTALL_DIR/.ScreenCaptureAll.install.XXXXXX")
ditto "$APP" "$INSTALL_STAGE/new.app" || fail "Cannot stage the app; previous copy untouched"
codesign --verify --deep --strict "$INSTALL_STAGE/new.app" || fail "Staged app signature is invalid"
check_quarantine "$INSTALL_STAGE/new.app"
check_destination
if [[ -e "$TARGET" ]]; then
  mv "$TARGET" "$INSTALL_STAGE/previous.app" || fail "Cannot back up the existing app"
fi
mv "$INSTALL_STAGE/new.app" "$TARGET" || fail "Cannot install staged app"
NEW_INSTALLED=1
codesign --verify --deep --strict "$TARGET" || fail "Installed app signature is invalid"
check_quarantine "$TARGET"
COMPLETE=1
echo "Installed ScreenCaptureAll $VERSION at $TARGET"
echo "Open it from Applications when ready. The installer has not launched it."
echo "For updates, use Check for Updates in the app when available, or quit and rerun this installer with --replace."
