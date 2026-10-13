#!/bin/bash
# Public releases require Developer ID signing and Apple notarization.
# Release credentials are supplied through encrypted GitHub Actions secrets.
set -euo pipefail
cd "$(dirname "$0")/.."
# This exact preflight is shared by the workflow and the actual signing path.
# GitHub exposes absent secrets as empty environment values; any nonempty API
# credential selects API auth and requires the whole team-key trio.
preflight() {
  for name in MACOS_CERTIFICATE_P12 MACOS_CERTIFICATE_PASSWORD MACOS_SIGN_IDENTITY; do
    [ -n "${!name:-}" ] || { echo "required release secret is absent: $name" >&2; return 1; }
  done
  case "$MACOS_SIGN_IDENTITY" in
    "Developer ID Application:"*) ;;
    *) echo "public releases require a Developer ID Application identity" >&2; return 1 ;;
  esac
  if [ -n "${MACOS_NOTARY_KEY_ID:-}${MACOS_NOTARY_ISSUER_ID:-}${MACOS_NOTARY_KEY_P8:-}" ]; then
    NOTARY_AUTH="api"
    for name in MACOS_NOTARY_KEY_ID MACOS_NOTARY_ISSUER_ID MACOS_NOTARY_KEY_P8; do
      [ -n "${!name:-}" ] || { echo "required release secret is absent: $name" >&2; return 1; }
    done
  else
    NOTARY_AUTH="apple-id"
    for name in MACOS_NOTARY_APPLE_ID MACOS_NOTARY_TEAM_ID MACOS_NOTARY_APP_PASSWORD; do
      [ -n "${!name:-}" ] || { echo "required release secret is absent: $name" >&2; return 1; }
    done
  fi
  MACOS_NOTARY_PROFILE="${MACOS_NOTARY_PROFILE:-plume-notary}"
}

PREFLIGHT_ONLY=false
case "$#" in
  0) ;;
  1) if [ "$1" = "--preflight" ]; then PREFLIGHT_ONLY=true
     else echo "usage: release-signed.sh [--preflight]" >&2; exit 64; fi ;;
  *) echo "usage: release-signed.sh [--preflight]" >&2; exit 64 ;;
esac
preflight
if [ "$PREFLIGHT_ONLY" = true ]; then
  echo "release credential preflight passed (notary authentication: $NOTARY_AUTH)"
  exit 0
fi

WORK=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/plume-signing.XXXXXX")
KEYCHAIN="$WORK/signing.keychain-db"
KEYCHAIN_MAY_EXIST=false

# security prints one quoted path per line. Strip only the surrounding whitespace
# and quotes: read -r and quoted arrays preserve spaces and shell metacharacters.
# Never eval the output or split it on whitespace.
read_user_keychains() {
  SEARCH_KEYCHAINS=()
  security list-keychains -d user > "$WORK/search-list.txt" || return 1
  local entry
  while IFS= read -r entry || [ -n "$entry" ]; do
    entry="${entry#"${entry%%[![:space:]]*}"}"
    entry="${entry%"${entry##*[![:space:]]}"}"
    [ -n "$entry" ] || continue
    case "$entry" in
      \"*\") entry="${entry#\"}"; entry="${entry%\"}" ;;
      *) echo "could not parse the user keychain search list" >&2; return 1 ;;
    esac
    [ -n "$entry" ] || { echo "empty user keychain search-list entry" >&2; return 1; }
    SEARCH_KEYCHAINS+=("$entry")
  done < "$WORK/search-list.txt"
}

register_keychain() {
  read_user_keychains || return 1
  local updated=("$KEYCHAIN") entry
  for entry in ${SEARCH_KEYCHAINS[@]+"${SEARCH_KEYCHAINS[@]}"}; do
    [ "$entry" = "$KEYCHAIN" ] || updated+=("$entry")
  done
  security list-keychains -d user -s "${updated[@]}"
}

unregister_keychain() {
  # Read again instead of restoring a snapshot: preserve entries added/removed
  # by other processes during the build, along with their current order.
  read_user_keychains || return 1
  local remaining=() entry found=false
  for entry in ${SEARCH_KEYCHAINS[@]+"${SEARCH_KEYCHAINS[@]}"}; do
    if [ "$entry" = "$KEYCHAIN" ]; then found=true
    else remaining+=("$entry"); fi
  done
  if [ "$found" = true ]; then
    security list-keychains -d user -s ${remaining[@]+"${remaining[@]}"} || return 1
  fi
}

cleanup() {
  local status=$?
  trap - EXIT
  # Finish cleanup even if another handled signal arrives while it is running.
  trap '' INT TERM
  if [ "$KEYCHAIN_MAY_EXIST" = true ]; then
    if ! unregister_keychain; then
      echo "could not remove the temporary signing keychain from the search list" >&2
      [ "$status" -ne 0 ] || status=1
    fi
    if ! security delete-keychain "$KEYCHAIN" >/dev/null 2>&1; then
      echo "could not delete the temporary signing keychain" >&2
      [ "$status" -ne 0 ] || status=1
    fi
  fi
  if ! rm -rf "$WORK"; then
    echo "could not remove temporary signing files" >&2
    [ "$status" -ne 0 ] || status=1
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
umask 077
KEYCHAIN_PASSWORD=$(openssl rand -hex 32)
printf '%s' "$MACOS_CERTIFICATE_P12" | base64 --decode > "$WORK/certificate.p12"
# Mark before creation so cleanup also handles a partially failed create/register.
KEYCHAIN_MAY_EXIST=true
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
register_keychain
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$WORK/certificate.p12" -k "$KEYCHAIN" \
  -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
rm -f "$WORK/certificate.p12"
# Explicitly store the profile in the temporary keychain: its secret name alone
# is not a profile provisioned on an ephemeral runner.
if [ "$NOTARY_AUTH" = "api" ]; then
  # Retain this private key until both submissions finish; EXIT cleanup removes it.
  printf '%s' "$MACOS_NOTARY_KEY_P8" > "$WORK/notary-key.p8"
  chmod 600 "$WORK/notary-key.p8"
  xcrun notarytool store-credentials "$MACOS_NOTARY_PROFILE" --keychain "$KEYCHAIN" \
    --key "$WORK/notary-key.p8" --key-id "$MACOS_NOTARY_KEY_ID" \
    --issuer "$MACOS_NOTARY_ISSUER_ID" >/dev/null
else
  xcrun notarytool store-credentials "$MACOS_NOTARY_PROFILE" --keychain "$KEYCHAIN" \
    --apple-id "$MACOS_NOTARY_APPLE_ID" --team-id "$MACOS_NOTARY_TEAM_ID" \
    --password "$MACOS_NOTARY_APP_PASSWORD" >/dev/null
fi

# Build ad hoc, then seal once with the explicitly selected temporary keychain.
./scripts/bundle.sh --output dist --arch arm64
codesign --force --options runtime --timestamp --keychain "$KEYCHAIN" \
  --entitlements packaging/plume.entitlements --sign "$MACOS_SIGN_IDENTITY" dist/Plume.app
codesign --verify --deep --strict --verbose=2 dist/Plume.app
notarize() {
  xcrun notarytool submit "$1" --keychain-profile "$MACOS_NOTARY_PROFILE" \
    --keychain "$KEYCHAIN" --wait --output-format plist > "$WORK/result.plist"
  STATUS=$(/usr/libexec/PlistBuddy -c 'Print :status' "$WORK/result.plist")
  [ "$STATUS" = "Accepted" ] || { echo "notarization status: $STATUS" >&2; exit 1; }
}
ditto -c -k --sequesterRsrc --keepParent dist/Plume.app "$WORK/notarize.zip"
notarize "$WORK/notarize.zip"
xcrun stapler staple dist/Plume.app
xcrun stapler validate dist/Plume.app
codesign --verify --deep --strict --verbose=2 dist/Plume.app
spctl --assess --type execute --verbose=2 dist/Plume.app
# Final ZIP is made from the stapled app, retaining installer compatibility.
ditto -c -k --sequesterRsrc --keepParent dist/Plume.app dist/plume-macos-arm64.zip
./scripts/dmg.sh --app dist/Plume.app --output dist --sign "$MACOS_SIGN_IDENTITY" --keychain "$KEYCHAIN"
codesign --verify --strict --verbose=2 dist/plume-macos-arm64.dmg
notarize dist/plume-macos-arm64.dmg
xcrun stapler staple dist/plume-macos-arm64.dmg
xcrun stapler validate dist/plume-macos-arm64.dmg
codesign --verify --strict --verbose=2 dist/plume-macos-arm64.dmg
spctl --assess --type open --context context:primary-signature --verbose=2 dist/plume-macos-arm64.dmg
(cd dist; shasum -a 256 plume-macos-arm64.zip > plume-macos-arm64.zip.sha256)
(cd dist; shasum -a 256 plume-macos-arm64.dmg > plume-macos-arm64.dmg.sha256)
