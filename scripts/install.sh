#!/usr/bin/env bash
# Plume installer.
#   curl -fsSL https://plume.sprintmob.com/install.sh | sh
#   curl -fsSL https://plume.sprintmob.com/install.sh | sh -s -- --tag v0.1.0-rc.1
#
# Fetches the latest stable arm64 macOS build (or an explicit release tag),
# installs ~/Applications/Plume.app and ~/.local/bin/plume without admin rights,
# and strips the quarantine xattr.
#
# On Gatekeeper, since half of what people believe about it is wrong: quarantine
# is applied by the *downloader*, and curl does not apply it. So this path is
# not blocked at all, and the xattr strip below is belt and braces for the case
# where you fetched the zip in a browser first. What a browser download of an
# ad-hoc signed .app does get is "Plume is damaged and can't be opened", which
# is what macOS says about anything it cannot verify.
#
# Apple Silicon only — WhisperKit uses the Apple Neural Engine via CoreML,
# which only ships on M-series chips.

set -euo pipefail

REPO="sprintmob/plume"
APP_NAME="Plume"
EXEC_NAME="plume"
APP_DIR="$HOME/Applications"
SHIM_DIR="$HOME/.local/bin"
SHIM="$SHIM_DIR/${EXEC_NAME}"
ASSET="plume-macos-arm64.zip"

red()    { printf "\033[31m%s\033[0m\n" "$*" >&2; }
green()  { printf "\033[32m%s\033[0m\n" "$*"; }
dim()    { printf "\033[2m%s\033[0m\n" "$*"; }

# 1. arguments and sanity
TAG=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tag)
            if [ "$#" -lt 2 ] || [ -z "$2" ]; then
                red "usage: sh install.sh [--tag v0.1.0-rc.1]"
                exit 2
            fi
            TAG="$2"
            shift 2
            ;;
        *)
            red "usage: sh install.sh [--tag v0.1.0-rc.1]"
            exit 2
            ;;
    esac
done

if [ "$(uname -s)" != "Darwin" ]; then
    red "plume is macOS-only (detected $(uname -s))"
    exit 1
fi

ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    red "plume requires Apple Silicon (detected $ARCH)"
    red "the on-device inference engine uses the Apple Neural Engine, which Intel Macs don't have."
    exit 1
fi

for cmd in curl ditto shasum codesign; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        red "missing dependency: $cmd"
        exit 1
    fi
done

# 2. resolve the latest stable release unless a tag was requested explicitly.
if [ -z "$TAG" ]; then
    dim "→ resolving latest stable release..."
    TAG=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
        | sed -nE '/"tag_name"/{s/.*"tag_name": *"([^"]+)".*/\1/;p;q;}')
fi

case "$TAG" in
    v[0-9]*) ;;
    *) red "invalid release tag: $TAG"; exit 1 ;;
esac
case "$TAG" in
    *[!A-Za-z0-9._-]*) red "invalid release tag: $TAG"; exit 1 ;;
esac
dim "  ${TAG}"

URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"

# 3. download + verify
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

dim "→ downloading ${ASSET}..."
curl -fsSL "$URL" -o "$TMP/${ASSET}"

# The release workflow publishes ${ASSET}.sha256 alongside the archive.
# Verify it: this installs an ad-hoc signed app and strips its quarantine flag,
# so the checksum is the only integrity check there is.
dim "→ verifying checksum..."
curl -fsSL "${URL}.sha256" -o "$TMP/${ASSET}.sha256"
( cd "$TMP" && shasum -a 256 -c "${ASSET}.sha256" >/dev/null ) || {
    red "checksum mismatch for ${ASSET} — refusing to install"
    exit 1
}

# ditto rather than unzip: some unzip builds drop extended attributes, and the
# code signature seal is stored in them.
dim "→ extracting..."
ditto -x -k "$TMP/${ASSET}" "$TMP/extracted"

APP="$TMP/extracted/${APP_NAME}.app"
if [ ! -d "$APP" ]; then
    red "archive did not contain ${APP_NAME}.app"
    exit 1
fi

# 4. strip quarantine, recursively. A bundle is a directory: -d on one file
# leaves the xattr on everything inside it, which is most of the bundle.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

# 5. verify the signature before installing. A corrupted bundle produces
# "Plume is damaged", which users read as "malware". Catching it here with a
# real message is worth the line.
dim "→ verifying signature..."
if ! codesign --verify --strict "$APP" 2>/dev/null; then
    red "the downloaded app failed signature verification — refusing to install"
    red "this means the archive is corrupt, not that it is malicious."
    exit 1
fi

# 6. install only inside the current user's home directory. Refuse path links
# that could redirect a write into a system location.
for path in "$APP_DIR" "$HOME/.local" "$SHIM_DIR" "$APP_DIR/${APP_NAME}.app" "$SHIM"; do
    if [ -L "$path" ]; then
        red "refusing to install through a symbolic link: $path"
        exit 1
    fi
done
mkdir -p "$APP_DIR" "$SHIM_DIR"

dim "→ installing to ${APP_DIR}/${APP_NAME}.app..."
rm -rf "${APP_DIR}/${APP_NAME}.app"
ditto "$APP" "${APP_DIR}/${APP_NAME}.app"

# The CLI is the app. A shim and not a symlink: Bundle.main does not resolve
# through a symlink, so a symlinked plume would read a different preferences
# domain than the daemon. See docs/adr/0008-ship-a-real-app-bundle.md.
dim "→ writing ${SHIM}..."
cat > "$SHIM" <<SHIM_BODY
#!/bin/sh
# ${SHIM}: the CLI is the app.
exec "${APP_DIR}/${APP_NAME}.app/Contents/MacOS/${EXEC_NAME}" "\$@"
SHIM_BODY
chmod 755 "$SHIM"

green "✓ Plume ${TAG} installed at ${APP_DIR}/${APP_NAME}.app"
echo

if [ -d "$HOME/Library/Application Support/parrot" ] \
   || [ -f "$HOME/Library/LaunchAgents/com.digimata.parrot.plist" ]; then
    echo "found a parrot install. carry it over first, or the models download again:"
    echo "  ${SHIM} install --migrate"
    echo
fi

echo "next:"
echo "  ${SHIM} setup                       # grant mic + accessibility"
echo "  ${SHIM} install --launch-at-login   # (optional) start at login"
echo "  ${SHIM}                             # run the daemon"
echo
echo "To use 'plume' without its full path, add ${SHIM_DIR} to your PATH yourself."
