# Guided installation and signed public distribution

Plume keeps SwiftPM, its macOS 14 / arm64 target and `com.sprintmob.plume` identity.
A separate onboarding window prepares required permissions, a hold-to-talk key
and the selected model before the event tap starts. `DaemonState.preparation`
distinguishes selected metadata from a loaded model. Warmup is asynchronous and
retryable; no semaphore blocks AppKit, and persistent failures stay visible
instead of exiting into launchd's KeepAlive loop. Optional doctor warnings remain
diagnostics. Completion is a remembered UserDefaults choice written only by
Finish; session history stays in RAM.

A per-user process-lifetime flock prevents two bundled daemons from listening.
Reopening signals the existing instance; an old running bundle without the lock
is detected and must be quit. Launch-at-login reuses ADR-0008's per-user plist,
privacy choices, Interactive process and umask. The GUI does not boot out its own
owner to enable it. Migration is still explicit, and SMAppService is still refused.
Transient DMG/translocation/read-only launches provide installation guidance
before asking for permission or registering a launch agent.

## Superseding ADR-0008's public ad-hoc distribution

ADR-0008's Gatekeeper discussion describes the ad-hoc release that existed then;
that history remains accurate for v0.1.0 and local builds. Future public `v*`
releases now require Developer ID credentials and notarization. The pipeline
staples and validates the app before making the compatible ZIP, then separately
signs/notarizes/staples/validates its drag-to-Applications DMG. Missing credentials
fail early and never select ad hoc for a tag. Temporary signing material is
cleaned on success and failure. Apple's enrollment/certificate prerequisite and
real browser validation remain manual release work.

The primary site/README download action is gated by an explicit deterministic
`distribution.json` setting. It stays on the existing CLI installer until a stable
release actually contains the signed DMG, then becomes an ordinary link to the
latest stable DMG. There is no runtime API availability request or auto-updater.
