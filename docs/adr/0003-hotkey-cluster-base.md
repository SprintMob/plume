# Base the hotkey cluster on #4, kept on top of #10

Four upstream PRs — #4, #7, #10, #18 — independently fix the same thing: the
README has advertised `--hotkey right-option` since before this fork existed
while `HotkeyMonitor` had `.maskSecondaryFn` hard-coded. ADR-0002 recorded the
choice between them as open and gating wave 2. It is now settled.

**#4 is the base.** Its `Hotkey` enum is a strict superset of #10's: nine
modifiers against two, each filtered on its virtual keycode so the other instance
of the modifier stays usable for normal typing. The triage board recommended #10
for having the smallest surface, but a superset is not a larger surface — it is
the same mechanism with more cases in one switch.

**#10 is kept underneath rather than replaced.** It merged first and its
`init(mask:keycode:debug:)` is now the designated initializer, with the keycode
filter in `handle()`; #4's enum arrives beside it and resolves a name to that
pair through a convenience init. What #4 did replace is #10's manual string
switch in `Parrot.swift`, now an `ExpressibleByArgument` conformance, which also
buys argument validation and the value list in `--help`.

Neither PR is only about the README promise. Third-party keyboards handle Fn
entirely in firmware and never send it to the host, so before this the daemon
could not be triggered at all on those machines.

## Consequences

- **#7** (adpadillar) is superseded as written — its author flags it as
  unreviewed generated code — but its reasoning about firmware-local Fn is the
  reasoning above, and its persistence and menu bar ideas are worth rewriting on
  this base rather than merging.
- **#18** (vipergsm) is reduced to one thing worth isolating: upstream defect B4,
  the crash when the audio format changes mid-session, where `installTap` reads
  `outputFormat(forBus: 0)` before `engine.start()`. Its language forcing is
  already covered by #23, merged in this batch. Nothing else in it needs to land.
- The launch agent bakes the chosen modifier into its `ProgramArguments`, so
  changing the hotkey for a daemonized install means re-running
  `parrot install --launch-at-login --hotkey <name>`. Nothing persists it
  otherwise.

This decision is independent of #26, which stays open.
