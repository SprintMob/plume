---
name: Bug report
about: Something Plume does that it should not
labels: needs-triage
---

**What happened, and what you expected instead.**

**`plume doctor` output.** Paste it whole. It is the single most useful thing in
a report about this app: it says which permissions are granted, which model is
active, and whether the launch agent is pointing anywhere sensible.

```
$ plume doctor

```

**Version and machine.**

- `plume --version`:
- macOS version:
- Mac model (Apple Silicon only):
- Installed via: `curl … | sh` / built from source / other

**Which app you were dictating into**, if the bug involves text landing in the
wrong place or not landing at all. Chromium and Electron apps have their own
section in the architecture notes, and knowing which one it was usually settles
the question.

**Anything in the log**, if you run the daemon with `--log-file`. Transcript
text is never in there, so it is safe to paste.
