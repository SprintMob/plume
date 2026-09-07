# Ship a real `.app` bundle

Plume now ships as `Plume.app`, assembled by `scripts/bundle.sh` from
`packaging/Info.plist.in`, with `/usr/local/bin/plume` reduced to a three-line
shim that `exec`s the binary inside it.

The cost is not small. It rewrites installation, signing, the launch agent and
CI, for an app with no main window and no permanent dock icon. So the argument
had better not be decoration, and it is not.

## The argument is TCC, not the icon

An app icon needs no bundle. `NSApp.applicationIconImage` sets one at runtime,
and `docs/architecture.md` has been right about that all along. If this were
about looks it would be three lines, not four files and a migration.

What needs a bundle is **who macOS thinks is asking for permission**. An
Accessibility grant is anchored on the designated requirement of the code that
requested it. Unbundled, that code is whichever process launched the daemon, so
the grant attaches to Terminal, or iTerm, or Ghostty, or launchd. The README has
documented this as a "TCC quirk worth knowing" since the first wave, and
`Doctor.checkAccessibility` has to run `ps` on the parent process to guess which
application to name in its own remediation. That is not a quirk. It is the
permission model working correctly against a program that declined to identify
itself, and the consequences are real: switching terminals loses the grant, and
`Setup.swift` has to tell the user, truthfully and absurdly, that these
permissions "attach to your terminal app, not plume itself."

A bundle with a stable `CFBundleIdentifier` ends it. Plume asks for its own
permissions, appears under its own name in System Settings, and keeps the grant
when you change terminals. That is a functional defect fixed, and it is what
pays for the packaging work.

Two smaller things fall out for free, and neither would have justified the
change alone. `NSMicrophoneUsageDescription` becomes expressible, which it has
to be: a bundled app that calls `AVCaptureDevice.requestAccess(for: .audio)`
without that key is killed outright by TCC, and today it only works because the
terminal owns the grant. And `Contents/Resources/` gives the two SwiftPM
resource bundles somewhere to live. `swift-transformers_Hub.bundle` holds
tokenizer configs that `Bundle.module` loads with a generated accessor that
calls `fatalError` when it cannot find them; the bare
`/usr/local/bin/plume` shipped without it, which was a latent crash on every
path that falls back to the packaged configs.

## The honest corollary

The bundle makes one thing **worse**.

Gatekeeper applies only to quarantined code, and it is the downloader that
applies the quarantine. `curl … | sh` does not, so the install path this project
actually recommends is unchanged. But a `.app` downloaded through a browser is
quarantined, and for an ad-hoc signature the message is "Plume is damaged and
can't be opened", which is harsher than the "unidentified developer" dialog a
Developer ID build without notarization would get. On macOS 15 and later,
right-click → Open no longer works around it.

So the honest statement is narrow: **the browser path gets worse, the
`curl | sh` path is unchanged.** The README says so in those words.

The other cost is recurring. An ad-hoc signature anchors the designated
requirement on the `cdhash`, so every release is a different application to TCC
and every update costs the user their Accessibility grant. That is the argument
for buying a Developer ID, and it is worth writing down that the argument is
this and not Gatekeeper: a certificate anchors the requirement on the team,
which every future build satisfies.

## `SMAppService` is reopened, and refused for different reasons

`Install.swift` used to justify its hand-written LaunchAgent plist with "we
deliberately do NOT use `SMAppService.mainApp` — that requires a full `.app`
bundle." That premise is now gone. The conclusion survives, on four losses that
have nothing to do with bundles:

1. **`KeepAlive: {SuccessfulExit: false}`.** `SMAppService.mainApp` gives no
   control over it. The comment in `Install.swift` documents the umask bug where
   `KeepAlive` turned a warmup `EACCES` into a relaunch loop; that policy is
   understood and deliberate.
2. **`Umask: 0o077`.** No equivalent. It was a shipped bug, fixed on a real
   install, and `InstallUmaskTests` exists to keep it fixed.
3. **`ProcessType: Interactive`.** This is what lets the daemon promote itself
   to `.regular` in a GUI session, which is what makes the settings window
   ADR-0007 argued for work under launchd at all.
4. **`StandardOutPath` / `StandardErrorPath`.** The whole of `--log-file` and
   the privacy argument around it.

`SMAppService.mainApp` also passes no `ProgramArguments`, so `run --skip-doctor`
is inexpressible, and `SMAppService.agent(plistName:)` keeps a plist but
requires it to be immutable inside `Contents/Library/LaunchAgents/`, which kills
the per-user `--log-file` choice.

What it would buy is a toggle in System Settings → Login Items and no
`launchctl` to shell out to. That does not pay for four behaviours this repo has
already fought for and documented.

## The CLI is a shim, and that was measured

`/usr/local/bin/plume` could have been a symlink. It is not, and the reason is
not caution:

```
$ ln -s …/Plume.app/Contents/MacOS/plume /tmp/plume-link
$ /tmp/plume-link --version
dev
$ /usr/local/bin/plume --version      # the shim
0.0.5
```

`--version` reads `CFBundleShortVersionString` out of `Bundle.main`. Through the
symlink it reports `dev`, which means `Bundle.main` did not resolve to the
bundle, which means `bundleIdentifier` is nil there. So `plume doctor` run
through a symlink would take the process-name preferences domain while the
daemon in the bundle takes `com.sprintmob.plume`. Two domains:
`plume install --hotkey right-option` would write where the daemon never reads,
and the menu bar would appear to ignore the setting. That is precisely the
failure [ADR-0004](./0004-settings-in-userdefaults.md) exists to prevent,
reintroduced silently. The shim costs three lines and makes `argv[0]`
unambiguous.

The launch agent points at neither. `ProgramArguments[0]` must be a path inside
the bundle: pointing launchd at the shim would have launchd supervise a
`/bin/sh` and would detach the TCC attribution from the app. The shim is for
humans. `Doctor.checkLaunchAgentArgs` now enforces the invariant from the other
side.

## Consequences

- **The preferences domain moves** from `plume` (the process name) to
  `com.sprintmob.plume` (the bundle identifier), so remembered choices need
  migrating. This does not supersede ADR-0004: its substance is one `*Store` per
  concern in `UserDefaults` with flag-then-remembered-then-default precedence,
  and all of that is untouched. Only the domain those defaults live in moves.
- **TCC permissions move from the terminal to Plume.** `Setup.swift` telling the
  user the permissions attach to their terminal becomes false, in the good
  direction, and is rewritten.
- **An ad-hoc signature costs the Accessibility grant on every update.**
  `scripts/install-local.sh` keeps its `cdhash` guardrail, which fails the build
  rather than let a signature that would not survive the next build reach
  `~/Applications`.
- **The browser download path is blocked by Gatekeeper**; `curl | sh` is not.
- **The saved window frame resets.** The autosave name went from
  `parrot.settings` to `plume.settings` and no migration key is spent on a
  rectangle.
- **`doctor` grows checks.** `ProgramArguments[0]` must exist and must be inside
  a `.app`; a stale agent naming a deleted binary used to be entirely invisible.
- **`plume --version` exists**, reading the same plist the bundle carries, and
  degrades to `dev` unbundled.

### Superseded

- `docs/architecture.md`, goal 1 and the "Why Swift" closing line: "ship a
  single binary … there is no `.app` bundle, no menubar entry, no dock icon."
  All three clauses are false, and the last two were already false as of waves 2
  and 3.
- The "TCC quirk worth knowing" section of `docs/architecture.md` and its
  counterpart in the README. The quirk is what the bundle removes.
- The `SMAppService` justification in `Install.swift`, as above.

### Not superseded, despite appearances

[ADR-0007](./0007-a-settings-window-and-a-session-history.md) loses a premise
but keeps its conclusion. Its consequence read "there is no `.app` bundle, so
the main menu is built in code"; there is one now, and the menu is still built
in code, because a `MainMenu.nib` needs Xcode and `ibtool`, which this repo does
not have and does not want. The justification changes from "there is no bundle"
to "there is no nib, because there is no Xcode project."
