#!/bin/bash
# Regenerate Design/icon/plume.icns from the SVG sources.
#
# The .icns is committed. This repo is going open source, and a contributor on
# a clean checkout should not need librsvg to get an app with an icon. This
# script exists for when the source changes, not for every build.
#
# Two sources, and which one drives which size is the detail that gets missed.
# At 64px the true mark's inter-bar gap is 1.04px, so downscaling the 1024
# source produces the same grey slab the menu bar glyph was redrawn to avoid.
# So everything at or below 64px comes from the open-gap cut instead. It is
# what makes the difference between an icon that is crisp in the Finder and
# mush in the Dock at small sizes.

set -euo pipefail
cd "$(dirname "$0")/.."

ICON_DIR="Design/icon"
SOURCE="$ICON_DIR/plume-icon.svg"
SOURCE_SMALL="$ICON_DIR/plume-icon-small.svg"
OUT="$ICON_DIR/plume.icns"
SET=$(mktemp -d)/plume.iconset
mkdir -p "$SET"
trap 'rm -rf "$(dirname "$SET")"' EXIT

# rsvg-convert when it is installed, AppKit otherwise. Same output either way;
# the fallback means a clean checkout can regenerate this with nothing but Xcode.
render() {
    svg="$1"; shift
    if command -v rsvg-convert >/dev/null 2>&1; then
        while [ $# -gt 0 ]; do
            rsvg-convert -w "$1" -h "$1" "$svg" -o "$2"
            echo "  $1px → $(basename "$2")"
            shift 2
        done
    else
        swift scripts/render-svg.swift "$svg" "$@"
    fi
}

echo "small sizes, from the open-gap cut:"
render "$SOURCE_SMALL" \
    16 "$SET/icon_16x16.png" \
    32 "$SET/icon_16x16@2x.png" \
    32 "$SET/icon_32x32.png" \
    64 "$SET/icon_32x32@2x.png"

echo "large sizes, from the true mark:"
render "$SOURCE" \
    128 "$SET/icon_128x128.png" \
    256 "$SET/icon_128x128@2x.png" \
    256 "$SET/icon_256x256.png" \
    512 "$SET/icon_256x256@2x.png" \
    512 "$SET/icon_512x512.png" \
    1024 "$SET/icon_512x512@2x.png"

iconutil -c icns "$SET" -o "$OUT"
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
