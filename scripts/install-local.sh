#!/bin/bash
# Build, sign and install plume locally.
#
# The signing step is what keeps macOS from asking for Accessibility again on
# every rebuild: an adhoc/linker signature has no certificate, so TCC anchors the
# grant to the binary's cdhash and a rebuild invalidates it. Signed with a stable
# identity, the designated requirement becomes
#   identifier "plume" and certificate leaf = H"..."
# which every later build satisfies.
#
# The identity is a self-signed code-signing certificate in the login keychain,
# trusted for codeSign in the user domain (no admin needed). Create it once:
#
#   openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 3650 \
#     -nodes -subj "/CN=Plume Local Signing" \
#     -addext "basicConstraints=critical,CA:false" \
#     -addext "keyUsage=critical,digitalSignature" \
#     -addext "extendedKeyUsage=critical,codeSigning"
#   openssl pkcs12 -export -inkey key.pem -in cert.pem -out id.p12 -passout pass:PASS \
#     -name "Plume Local Signing" -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
#   security import id.p12 -k ~/Library/Keychains/login.keychain-db -P PASS -T /usr/bin/codesign -A
#   security add-trusted-cert -p codeSign -k ~/Library/Keychains/login.keychain-db cert.pem
#
# The legacy PKCS#12 algorithms are required: OpenSSL 3 defaults produce a file
# the macOS Security framework cannot read.

set -euo pipefail

TARGET="${PLUME_INSTALL_PATH:-/usr/local/bin/plume}"
LABEL="com.digimata.parrot"
cd "$(dirname "$0")/.."

# The rename does not reach into the login keychain, and recreating the
# certificate is a keychain operation only you can run. So: prefer the new
# name, fall back to the one this machine already has, and say which.
IDENTITY="${PLUME_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  identities=$(security find-identity -v -p codesigning)
  if printf '%s' "$identities" | grep -q "Plume Local Signing"; then
    IDENTITY="Plume Local Signing"
  elif printf '%s' "$identities" | grep -q "Parrot Local Signing"; then
    IDENTITY="Parrot Local Signing"
    echo "note: signing with 'Parrot Local Signing', the pre-rename identity" >&2
  else
    echo "no local signing identity found — see the header of this script" >&2
    exit 1
  fi
elif ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo "no code-signing identity named '$IDENTITY' — see the header of this script" >&2
  exit 1
fi

swift build -c release

# Sign in the build directory: codesign writes a temporary file beside its target
# and /usr/local/bin is root-owned.
codesign -f -s "$IDENTITY" --identifier plume .build/release/plume

requirement=$(codesign -d --requirements - .build/release/plume 2>&1 | tail -1)
case "$requirement" in
  *cdhash*)
    echo "signature still anchored to cdhash — the grant would not survive:" >&2
    echo "  $requirement" >&2
    exit 1
    ;;
esac

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
sleep 1
cat .build/release/plume > "$TARGET"
chmod 755 "$TARGET"
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$LABEL.plist"

echo "installed: $TARGET"
echo "requirement: $requirement"

# The daemon's output goes to /dev/null unless the plist was generated with
# `plume install --launch-at-login --log-file`, which points it at
# ~/Library/Logs/plume.log (0600). Read the plist rather than guessing: this
# script reinstalls the binary, it does not regenerate the agent.
log=$(/usr/libexec/PlistBuddy -c "Print :StandardErrorPath" \
    "$HOME/Library/LaunchAgents/$LABEL.plist" 2>/dev/null || echo "unknown")
if [ "$log" = "/dev/null" ]; then
  echo "log: discarded — reinstall the agent with 'plume install --launch-at-login --log-file' to keep it"
else
  echo "log: $log"
fi
