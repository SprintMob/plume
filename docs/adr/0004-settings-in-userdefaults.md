# Settings live in UserDefaults, changed from the menu bar

`docs/architecture.md` specified configuration as a TOML file at
`~/.config/parrot/config.toml` holding `model`, `hotkey`, `inject_mode` and
`overlay`, with CLI flags overriding it and "no settings UI; you edit the TOML".
That file was never written. Two upstream PRs merged in waves 2 and 3 answered the
same need a different way and shipped: #21 added `ModelStore` and #14 added
`InputDeviceStore`, both `UserDefaults`-backed, both chosen from the menu bar the
same document says does not exist.

So the decision was already taken by the merge queue; this records it and settles
the third case rather than letting a fourth spelling appear. **Settings persist in
`UserDefaults` behind one `*Store` type per concern, and are changed from the menu
bar.** `SettingsStore` joins the two, holding the push-to-talk modifier and the
injection mode.

The three candidate designs on the table were the TOML file above, #7's
`HotkeyPreferences` reading `UserDefaults.standard` through a hardcoded static, and
#26's `ParrotSettings` writing JSON to `~/Library/Application Support/parrot/`. The
merged pair decides it: matching what already ships costs nothing, needs no
dependency, and keeps one way of doing this instead of two. #26's shape stays
available if a settings file is ever wanted for its own sake — that decision is not
this one.

Precedence is the one `ModelStore` already documents: the flag wins for the launch
that passes it, else the remembered choice, else the default. A stored value that no
longer parses falls through to the default rather than failing the launch.

## Consequences

- **`parrot install` no longer bakes `--hotkey` or `--inject-mode` into the launch
  agent's `ProgramArguments`.** A flag there wins on every launch, so baking one
  would silently undo every menu-bar pick for exactly the daemonized users the menu
  bar exists for. `install --hotkey X` now records the choice instead. Agents
  written by earlier versions still carry the flags; `parrot doctor` warns when it
  finds them and says to re-run the install.
- **A menu-bar pick beats the flag the daemon launched with**, for that session and
  after. The flag is the starting value, not a lock — otherwise picking from the
  menu would appear to do nothing under a daemonized install.
- **The Fn key mapping check is now conditional.** `DoctorReport.run` takes the
  resolved modifier and only checks `AppleFnUsageType` when it is `fn`. That check
  hard-fails, and it gated startup, so before this a user on `--hotkey right-option`
  could be refused a launch over a key parrot was not watching.
- **`docs/architecture.md` §`Config` is superseded**, along with its "no menubar, no
  settings window, no preferences panel" line — the menu bar has carried Model and
  Input submenus since wave 3 and now carries four.
- This closes both gaps wave 2 recorded, and finishes what
  [ADR-0003](./0003-hotkey-cluster-base.md) left of #7. It is independent of #26,
  which stays open.
