#!/bin/bash
# Package an already sealed Plume.app with a drag-to-Applications shortcut.
# Local smoke: scripts/dmg.sh --app dist/Plume.app --output dist
# --sign requires a Developer ID identity; omission is explicitly ad hoc.
set -euo pipefail
# Distribution content must be readable after a drag into shared Applications.
# Runtime model/log privacy stays with the daemon and launch agent.
umask 022
cd "$(dirname "$0")/.."
APP="dist/Plume.app"
OUTPUT="dist"
SIGN_IDENTITY="-"
KEYCHAIN_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --app) APP="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --sign) SIGN_IDENTITY="$2"; shift 2 ;;
    --keychain) KEYCHAIN_ARGS=(--keychain "$2"); shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done
[ -d "$APP/Contents" ] || { echo "missing Plume.app at $APP" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/plume-dmg.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$OUTPUT"
DMG="$OUTPUT/plume-macos-arm64.dmg"
ditto "$APP" "$STAGE/Plume.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Install Plume.txt" <<'TEXT'
Install Plume

1. Drag Plume.app to the Applications shortcut.
2. Eject this disk image.
3. Open Plume from Applications and follow the guided setup.

Requires macOS 14 or later and Apple Silicon.
The recommended speech model downloads about 461 MB on first use.
Local ad-hoc builds are not notarized and cannot claim Gatekeeper approval.
TEXT
rm -f "$DMG"
hdiutil create -volname "Plume — drag to Applications" -srcfolder "$STAGE" \
  -ov -format UDZO "$DMG"
if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --sign - --timestamp=none "$DMG"
  echo "local ad-hoc DMG (not notarized): $DMG"
else
  codesign --force --sign "$SIGN_IDENTITY" --timestamp ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} "$DMG"
fi
codesign --verify --strict --verbose=2 "$DMG"
hdiutil verify "$DMG"
