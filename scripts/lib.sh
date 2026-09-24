# Identifiers shared by every script that builds, signs or installs plume.
#
# packaging/Info.plist.in is the source of truth for the *deployed* app: at
# runtime the daemon reads its label and its preferences domain out of
# CFBundleIdentifier, never out of a Swift literal. This file is the source for
# the scripts, and bundle.sh substitutes these values into the template, so the
# two cannot drift.
#
# One string is three things: the bundle identifier, the launchd label, and the
# preferences domain. Lowercase rather than com.sprintmob.Plume because it is
# also a filename in ~/Library/Preferences, where mixed case is noise.

APP_NAME="Plume"
EXEC_NAME="plume"
BUNDLE_ID="com.sprintmob.plume"
LABEL="$BUNDLE_ID"

# The label written by every version before the rename. Kept indefinitely: it
# is the only way anything can explain why two daemons are fighting over the
# same event tap.
LEGACY_LABEL="com.digimata.parrot"

# Reads the version the same way bundle.sh does, so install-local.sh and the
# CI workflow cannot disagree about it.
plume_version() {
  if [ -n "${PLUME_VERSION:-}" ]; then
    printf '%s' "$PLUME_VERSION"
    return
  fi
  tag=$(git describe --tags --match 'v*' --abbrev=0 2>/dev/null || true)
  if [ -n "$tag" ]; then
    printf '%s' "${tag#v}"
  else
    printf '0.0.0'
  fi
}

# The CLI is the app. A three-line shim rather than a symlink, and that is not
# a matter of taste: measured on 2026-09-06, `Bundle.main` does NOT resolve
# through a symlink to the .app. The same build reports version "dev" through
# `ln -s` and "0.0.5" through this shim, which means bundleIdentifier is nil
# through the link, which means `plume doctor` run from ~/.local/bin would
# take the process-name preferences domain while the daemon in the bundle takes
# com.sprintmob.plume. Two domains, and every remembered choice written to the
# one nothing reads. That is the failure ADR-0004 exists to prevent.
write_cli_shim() {
  app_path="$1"
  target="$2"
  cat > "$target" <<SHIM
#!/bin/sh
# $target: the CLI is the app.
exec "$app_path/Contents/MacOS/$EXEC_NAME" "\$@"
SHIM
  chmod 755 "$target"
}
