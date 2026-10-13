# Installing and distributing Plume

The live installation action remains the CLI installer until a stable signed DMG
has been published. The historical/current v0.1.0 release is ad hoc. Local builds
are also ad hoc unless an explicit Developer ID identity is provided.

The prepared browser path is:
[Download Plume for Mac](https://github.com/SprintMob/plume/releases/latest/download/plume-macos-arm64.dmg),
drag Plume into Applications, eject the disk image, then open Plume from
Applications. Requirements: macOS 14+ and Apple Silicon. Guided setup explains and
requests microphone and Accessibility access, lets you configure Fn (🌐) or
another modifier, prepares the selected model and offers a test field. A fresh
installation chooses Parakeet TDT v3, about 461 MB; remembered or explicit models
win. Dictation stays disabled until permissions, the key and the model are ready.
Downloads show progress; loading is a separate stage; failures remain visible
with Retry. Finish alone remembers completion. Closing setup keeps preparation
running, and Quit remains available. Launch at login is initially off.

Launching from a mounted disk image, read-only volume or app-translocation path
shows copy-to-Applications guidance rather than requesting permissions or
registering a temporary path. Existing `~/Applications/Plume.app` installs remain
supported. Reopening brings forward the existing daemon's setup or settings.
An older bundle already running needs to be quit before the new daemon can
listen. Migration stays an explicit `plume install --migrate` action.

## Enabling the download action

`distribution.json` is the only availability setting. Keep `dmgAvailable: false`
until a stable release containing `plume-macos-arm64.dmg` and its checksum is
published and browser/Gatekeeper checks pass. Then set `dmgAvailable: true` and
record the published `stableRelease` as `vX.Y.Z`. Run:

```sh
python3 scripts/build-distribution.py --update-readme
python3 scripts/build-distribution.py --check
```

Commit the setting and generated README copy together. The Pages build renders
an ordinary download link and installation instructions deterministically; it
never queries GitHub from a visitor's browser. With the switch off, it renders
the functioning CLI action. A prerelease is insufficient to enable the switch.

## Secure release provisioning

A maintainer must enroll the publishing organization in the Apple Developer
Program, obtain a **Developer ID Application** certificate and its private key,
and accept Apple's current agreements. This manual prerequisite cannot be
completed by changing the workflow. Do not commit credentials or send them in
issues, chat, logs or pull requests.

In the repository's GitHub Actions secrets settings, an authorized maintainer
must provide these secrets using GitHub's encrypted secret UI:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | Base64 of the password-protected certificate/key P12 exported securely by its owner |
| `MACOS_CERTIFICATE_PASSWORD` | P12 export password |
| `MACOS_SIGN_IDENTITY` | Exact `Developer ID Application: … (TEAMID)` identity |
| `MACOS_NOTARY_PROFILE` | A chosen profile name (not a pre-existing runner profile) |
| `MACOS_NOTARY_APPLE_ID` | Authorized Apple ID for notarization |
| `MACOS_NOTARY_TEAM_ID` | Developer team identifier |
| `MACOS_NOTARY_APP_PASSWORD` | Apple-generated app-specific password |

Restrict repository write/tag privileges and protect releases. Keep credentials
out of fork pull-request workflows. Rotate/revoke the app-specific password and
certificate secrets if access changes. This change does not create/export keys
or provision any credential.

Every `v*` tag fails before building if a credential is absent. Public artifacts
never fall back to ad hoc. `scripts/release-signed.sh` creates a temporary signing
keychain, imports the P12, explicitly creates the notarytool credentials profile
in that keychain, signs with hardened runtime, a secure timestamp and the existing
audio entitlement, and requires `Accepted`. It staples and validates the app,
then packages the compatible ZIP from that stapled app. It constructs, signs,
notarizes, staples and validates the DMG and writes SHA256 sidecars for both.
Its EXIT trap deletes certificate material and the temporary keychain on success
or failure. `workflow_dispatch` from an ordinary branch remains an ad-hoc smoke
build; it does not publish a release.

## Local smoke checks

```sh
./scripts/bundle.sh --output dist --arch arm64
./scripts/dmg.sh --app dist/Plume.app --output dist
plutil -lint dist/Plume.app/Contents/Info.plist
codesign --verify --deep --strict dist/Plume.app
hdiutil verify dist/plume-macos-arm64.dmg
```

Mount the DMG read-only and verify Plume.app, the Applications shortcut and
`Install Plume.txt`; eject it afterward. Do not treat an ad-hoc smoke build as
notarized. Real Developer ID/notarization/Gatekeeper validation and a fresh Mac
account's first microphone, Accessibility and dictation flow remain release gates
until actually exercised. The CLI ZIP asset and checksum names remain compatible
with `scripts/install.sh`.
