# The transcript always goes to the pasteboard

`docs/architecture.md` ruled the pasteboard out as an output — "No history,
transcript log, or clipboard manager. Output goes to the cursor and that's it" —
and `paste` mode honoured that literally. It snapshotted the pasteboard, wrote the
transcript, posted ⌘V, and put the snapshot back 0.25 s later; `type-unicode` never
touched the pasteboard at all. Only the transcript fallback left anything behind,
and only because a dictation with nowhere to land had to go somewhere.

That left every dictation with exactly one place to land, and three ways to lose
it. The focus probe spends up to 0.6 s in the accessibility API, twice, on an app
that may never answer — and everything downstream of it waits. An app that
silently drops synthesized unicode swallows a `type-unicode` delivery whole. And
paste is asynchronous in the receiver, so an app that reads the pasteboard after
the 0.25 s settle delay gets the user's old contents instead of the transcript.
Each failure is silent: `inject` returns nothing, so nobody finds out.

**Every non-empty transcript is now written to the pasteboard before the focus
probe runs, in both modes, and nothing is ever restored.** The snapshot-and-restore
machinery is deleted rather than made conditional. Ordering is the point: the write
happens before anything that can hang or refuse, so whatever the accessibility API
does next, the dictation is already somewhere the user can reach with ⌘V.

Two alternatives were weighed. **Copying only on a failed injection** keeps the
old clipboard intact in the common case, but there is no failure to detect — `⌘V`
posted into an app that ignores it looks exactly like success, and that is the case
most worth covering. **A menu-bar toggle**, in the shape ADR-0004 established for
settings, was rejected as surface for a behaviour that has one right answer: a
transcript nobody can reach is a bug in every configuration.

## Consequences

- **Whatever the user had copied is destroyed, images and files included.** The
  snapshot captured every representation of every item precisely so that dictating
  over a copied image did not silently wipe it; that protection is gone. This is
  the trade the change buys, taken on the understanding that clipboard history is
  a clipboard manager's job and not parrot's.
- **`type-unicode` no longer leaves the pasteboard alone.** That was half of its
  stated reason to exist. What remains is the delivery mechanism — it types rather
  than pastes — and its help text, the README and `architecture.md` are corrected
  to say so.
- **A transcript dictated at a password box is copied in plaintext, by decision.**
  It already was, since the fallback path covers `.secureField`, but incidentally.
  [ADR-0005](./0005-wake-chromium-accessibility.md) closes with "Nothing here
  weakens the secure-field refusal" — that remains true of injection, which is
  still refused at every rung of the walk, and was never true of the pasteboard.
- **The privacy claim is weaker by exactly one hop.** Parrot still writes no
  transcript to disk. A clipboard manager will, and pairing parrot with one is now
  the recommended setup rather than an incidental one.
- **One dictation is one clipboard entry.** The daemon copies before the probe and
  `inject` copies again, so `copyToPasteboard` skips a pasteboard already holding
  that exact string. The check is stateless, which also makes the fallback panel's
  Copy button meaningful: it rewrites exactly when something else has taken the
  pasteboard since.
- **`TextInjector` has tests for the first time.** Keystrokes leave through a
  `KeyStroke` seam rather than as `CGEvent`s, so a test can watch a delivery
  without posting a real ⌘V into whatever window has the focus — which, on a
  machine that has granted the terminal accessibility, is otherwise what happens.
