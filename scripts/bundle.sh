#!/bin/bash
# Assemble Plume.app, without Xcode.
#
# The bundle exists for TCC, not for looks. An Accessibility grant is anchored
# on the designated requirement of the code that asked for it; unbundled, that
# code is whichever terminal happened to launch the daemon, so the grant is
# attached to Terminal or iTerm or Ghostty and is lost the day you switch. A
# bundle with a stable identifier ends that. See docs/adr/0008-ship-a-real-app-bundle.md.
#
#   ./scripts/bundle.sh                      # dist/Plume.app, ad-hoc signed
#   ./scripts/bundle.sh --output /tmp/check  # somewhere else
#   ./scripts/bundle.sh --arch arm64         # what the release workflow passes
#   ./scripts/bundle.sh --sign "Developer ID Application: ..."
#
# PLUME_VERSION overrides the version; otherwise it comes from the latest v*
# tag, and is 0.0.0 outside a tagged checkout.

set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=lib.sh
. scripts/lib.sh

OUTPUT="dist"
SIGN_IDENTITY="-"
BUILD_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --output) OUTPUT="$2"; shift 2 ;;
    --arch)   BUILD_ARGS+=(--arch "$2"); shift 2 ;;
    --sign)   SIGN_IDENTITY="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done

VERSION=$(plume_version)

# bash 3.2, which is what /bin/bash is on macOS, treats "${arr[@]}" on an empty
# array as unbound under set -u, hence the guarded expansion below.
swift build -c release ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"}

# Ask SwiftPM where it put things rather than hardcoding
# .build/arm64-apple-macosx/release: --arch changes that path, and the two
# scripts that used to hardcode it disagreed about which one.
BIN_DIR=$(swift build -c release ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"} --show-bin-path)
BIN="$BIN_DIR/$EXEC_NAME"
[ -x "$BIN" ] || { echo "no executable at $BIN" >&2; exit 1; }

APP="$OUTPUT/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$EXEC_NAME"
printf 'APPL????' > "$APP/Contents/PkgInfo"

sed -e "s|@BUNDLE_ID@|$BUNDLE_ID|g" \
    -e "s|@EXEC_NAME@|$EXEC_NAME|g" \
    -e "s|@APP_NAME@|$APP_NAME|g" \
    -e "s|@VERSION@|$VERSION|g" \
    packaging/Info.plist.in > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" > /dev/null

# Not optional. swift-transformers looks its tokenizer configs up through
# Bundle.module, whose generated accessor calls fatalError when it cannot find
# the bundle, and it checks Bundle.main.resourceURL first. Shipping the bare
# binary, which is what happened until now, left a latent crash on every path
# that falls back to the packaged configs.
for resource in "$BIN_DIR"/*.bundle; do
  [ -e "$resource" ] || continue
  cp -R "$resource" "$APP/Contents/Resources/"
done

# Before codesign, never after. strip rewrites the Mach-O, which invalidates
# _CodeSignature/CodeResources, and macOS reports a bundle in that state as
# damaged rather than as unsigned.
strip -x "$APP/Contents/MacOS/$EXEC_NAME"

codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "built:   $APP"
echo "version: $VERSION"
echo "id:      $BUNDLE_ID"
codesign -d -r- "$APP" 2>&1 | sed 's/^/req:     /'
