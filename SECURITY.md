# Security

## Reporting

Use [GitHub's private vulnerability reporting](https://github.com/SprintMob/plume/security/advisories).
Do not open a public issue. The `security@sprintmob.com` alias will be added
here after it is active and tested.

Tell us what you can reproduce, on which macOS version, and what an attacker
gets. We will confirm receipt within three working days and tell you what we
intend to do.

## What is worth reporting

Plume runs as a login-time daemon, holds a `CGEventTap` over every keystroke,
and has the Accessibility permission. The interesting failures are:

- **Transcript disclosure.** Plume promises no transcript reaches disk. Any path
  that writes one, or leaks one to another process beyond the pasteboard write
  it documents, is a bug in the promise. Note that `--echo-transcripts` and
  `--dump-wav` exist and say what they do; those are not the bug.
- **The event tap.** Anything that turns the tap into a keylogger reachable by
  another process, or that lets injected text land somewhere it was not aimed.
- **Privilege and paths.** The launch agent, the `~/.local/bin/plume` shim,
  the model store. A writable path that ends up executed is the shape to look
  for.
- **The installer.** `scripts/install.sh` fetches over HTTPS, verifies a SHA-256
  against a published checksum, and verifies the code signature before it copies
  anything. A way past any of those three matters.

## What is already known and is not a vulnerability

- **Builds are ad-hoc signed and not notarized.** The README says so, in detail,
  and says what it costs. It is a shipping limitation, not a report.
- **Every transcript is written to the pasteboard**, deliberately and
  unconditionally, which means any clipboard manager on the machine keeps a copy.
  This is [ADR-0006](docs/adr/0006-transcript-always-on-the-pasteboard.md), the
  README states it, and it was a choice.
- **Versions up to v0.0.5 wrote transcripts to world-readable `/tmp` logs.**
  Fixed, and `plume doctor` still finds and offers to delete the old files.
