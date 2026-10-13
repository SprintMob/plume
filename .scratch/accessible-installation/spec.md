# Installer Plume sans Terminal

Status: ready-for-agent

## Objectif et choix approuvés

Une personne non technique sur Mac Apple Silicon, macOS 14+, télécharge un DMG,
glisse Plume dans Applications, ouvre l'application et réussit sa première dictée.
L'utilisateur a un compte Apple Developer actif. Aucun certificat Developer ID
ni secret MACOS_* n'est actuellement configuré. La release publique v0.1.0 est
ad hoc : les étapes Developer ID et notarisation de son workflow ont été sautées.
Les mises à jour de cette première livraison restent manuelles.

## Task 1: Distribution par DMG et premier lancement guidé

### Ownership and execution

Implementer owns all production code, tests, packaging, workflows, user-facing
documentation and relevant ADR changes. Controller owns this specification and
the issue status. You are not alone in the codebase: do not revert others' edits.
Work only in /private/tmp/plume-accessible-installation on feat/accessible-installation.
Do not spawn agents. Do not push, publish, install into the user's Applications,
modify their existing launch agent, or create/export private signing keys.
Commit implementation changes on this feature branch after verification.

### Global constraints

- Preserve SwiftPM (no Xcode project), macOS 14 minimum, arm64, bundle identifier
  com.sprintmob.plume, remembered choices/model store/session-history privacy.
- Existing CLI setup, doctor, models, install commands remain usable. The public
  ZIP asset plume-macos-arm64.zip and its checksum remain compatible with install.sh.
- Use existing SwiftUI/AppKit styling and English product language. No additional
  settings sidebar section; onboarding is a separate window/surface.
- Preserve ADR-0008's per-user launch agent mechanism and privacy/umask behavior;
  do not switch to SMAppService or rewrite migration as an automatic side effect.
- Do not add an auto-updater, port to Intel/other OS, or add telemetry/accounts.

### Distribution and release

- Add a reusable DMG packaging script producing plume-macos-arm64.dmg with
  Plume.app and a /Applications shortcut, and clear drag-and-drop instructions.
  It must also support local ad-hoc smoke builds without claiming notarization.
- Public tag releases v* must require Developer ID credentials, fail early if
  absent, and never silently fall back to ad-hoc signing. Local/ordinary CI
  bundle builds may remain ad hoc.
- Keep existing MACOS_CERTIFICATE_P12, MACOS_CERTIFICATE_PASSWORD,
  MACOS_SIGN_IDENTITY, MACOS_NOTARY_PROFILE. Add MACOS_NOTARY_APPLE_ID,
  MACOS_NOTARY_TEAM_ID, MACOS_NOTARY_APP_PASSWORD (app-specific password).
  Create the notarytool credentials profile in the runner's temporary signing
  keychain explicitly; a secret profile name is not an existing keychain profile.
- Sign the app with hardened runtime, secure timestamp and existing entitlements.
  Submit its ZIP, require Accepted status, staple and validate the app. Package
  the final ZIP from the stapled app. Build/sign/notarize/staple/validate the DMG
  from that app. Publish ZIP, DMG, and SHA256 sidecars, with signature checks.
  Ensure secret material/temp keychain cleanup on success and failure.
- Document secure GitHub secret setup and the remaining manual Apple prerequisite;
  never put credentials in repo or request credentials in conversation.
- Prepare site and README with a primary ordinary download link to
  https://github.com/SprintMob/plume/releases/latest/download/plume-macos-arm64.dmg
  and instructions download -> drag into Applications -> open Plume. This link
  must only go live when a stable release containing the DMG is published; until
  then retain the functioning CLI installation as the live primary action and
  stage the new action behind an explicit distribution availability setting.
  Prefer a simple deterministic build/configuration switch over runtime API fetch.
  Clearly show macOS 14+/Apple Silicon requirements and the initial model download.
- Update current-signature claims accurately: development/current v0.1.0 remains
  ad hoc until a new signed release is available. Historical ADR context stays
  historical; add an explicit superseding section/ADR for public signed releases.

### Startup and onboarding

- For bundled daemon launches, create NSApplication, menu bar and onboarding/
  remediation UI before doctor checks/model download. Do not block the main
  thread with the current warmup semaphore. Keep CLI diagnostics available.
- Introduce explicit preparation/readiness state in DaemonState so selected model
  metadata does not imply a loaded model. Reuse ActiveTranscriber.warmUp(onProgress:).
  Never start the hotkey event tap or allow capture until required permissions,
  hotkey configuration, and warmup are ready. Warnings about optional/legacy
  diagnostics must not become unrelated onboarding blockers.
- If launched from a mounted DMG/read-only app-translocation path, show guidance
  to copy to Applications and do not request permissions/register login launch
  against the transient path. Support existing ~/Applications installs.
- First-run sequence: welcome, microphone and Accessibility (explain purpose,
  user-initiated requests and Open System Settings actions), Fn configuration
  (keyboard settings or another supported hotkey), prepare recommended model,
  then a test text field with hold/speak/release instructions and Finish.
- Default to ModelRegistry.recommended(), currently Parakeet TDT v3 (~461 MB),
  while honoring an existing remembered/explicit model. Show actual progress,
  separate the loading stage from download, and Retry on any warmup/download
  error. Failures remain visible and do not trigger exit/relaunch loops.
- Refresh actual permission/configuration state on returning to the app and via
  a Check again button. Offer a controlled relaunch if macOS caches a permission;
  the relaunched process must open the actual installed app after the old exits.
- Remember onboarding completion in UserDefaults only on Finish with readiness.
  Interrupted onboarding resumes from actual system/model state. Existing
  completed installations launch quietly; missing permissions later show recovery.
- Offer launch at login, initially off, reusing existing Install mechanics. Avoid
  duplicate daemons/event taps when the GUI and launch agent overlap. Guarantee
  one bundled daemon per user (process-lifetime lock + reopen signaling), detect
  an older running bundle where necessary, and make reopening show the existing
  onboarding/settings window rather than silently failing.
- Quitting remains available while loading/blocked. Closing onboarding must not
  falsely mark it finished or discard progress. Preserve audio cleanup on exit.

### Verification

- Run focused behavior tests during iteration and swift test once before commit;
  build release, bundle, plist lint, scripts/check-rename.sh, shell syntax checks,
  and local ad-hoc DMG construction/mount-content smoke verification.
- Add meaningful tests for readiness transitions, denied/revoked permissions,
  Fn configuration, download failure/retry, interrupted/completed onboarding,
  singleton/reopen handling and launch-agent compatibility. Inject services where
  required so tests never alter host permissions, agents or model installations.
- If sandbox caches prevent Swift builds, request escalated execution (already
  authorized build/test scope) rather than misreporting a compiler/environment
  error as a code defect. You may reuse the existing root .build scratch path
  after the controller's baseline command completes; coordinate before doing so.
- Record exact commands/results and any existing unrelated build warning. Real
  Developer ID/notarization/Gatekeeper and fresh-account dictation verification
  must be reported pending unless actually exercised; do not fabricate evidence.

### Report

Write the full implementation/self-review/test report to the controller-provided
task-1-report.md. Return only status DONE/DONE_WITH_CONCERNS/BLOCKED/NEEDS_CONTEXT,
commits, one-line test results, concerns, and report path. The controller will
dispatch the separate reviewer after implementation; do not review via another agent.
