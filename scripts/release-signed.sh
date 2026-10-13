#!/bin/bash
# Public releases require Developer ID signing and Apple notarization.
# Credentials are GitHub Actions secrets, never command-line arguments or files in git.
set -euo pipefail
cd "$(dirname "$0")/.."
for name in MACOS_CERTIFICATE_P12 MACOS_CERTIFICATE_PASSWORD MACOS_SIGN_IDENTITY \
  MACOS_NOTARY_PROFILE MACOS_NOTARY_APPLE_ID MACOS_NOTARY_TEAM_ID MACOS_NOTARY_APP_PASSWORD; do
  [ -n "${!name:-}" ] || { echo "required release secret is absent: $name" >&2; exit 1; }
done
case "$MACOS_SIGN_IDENTITY" in
  "Developer ID Application:"*) ;;
  *) echo "public releases require a Developer ID Application identity" >&2; exit 1 ;;
esac
WORK=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/plume-signing.XXXXXX")
KEYCHAIN="$WORK/signing.keychain-db"
KEYCHAIN_PASSWORD=$(openssl rand -hex 32)
cleanup() {
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
umask 077
printf '%s' "$MACOS_CERTIFICATE_P12" | base64 --decode > "$WORK/certificate.p12"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$WORK/certificate.p12" -k "$KEYCHAIN" \
  -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
rm -f "$WORK/certificate.p12"
# Explicitly store the profile in the temporary keychain: its secret name alone
# is not a profile provisioned on an ephemeral runner.
xcrun notarytool store-credentials "$MACOS_NOTARY_PROFILE" --keychain "$KEYCHAIN" \
  --apple-id "$MACOS_NOTARY_APPLE_ID" --team-id "$MACOS_NOTARY_TEAM_ID" \
  --password "$MACOS_NOTARY_APP_PASSWORD" >/dev/null

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
