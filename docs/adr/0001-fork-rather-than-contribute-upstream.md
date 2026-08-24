# Fork parrot rather than contribute upstream

`digimata/parrot` has had no code commit since 2026-05-11, and its 25 open PRs are
all mergeable and clean, none reviewed, none commented on by the maintainer.
Sending our fixes there would put them at the back of a queue nobody is emptying,
so we fork and merge that queue ourselves.

## Consequences

- The work is merging and arbitrating other people's patches, not writing our own.
  Four of the five upstream defects (B1–B4) already have a PR; re-implementing them
  would be duplicated effort.
- New code is reserved for the six blind spots — the defects no open PR covers.
  Everything else is taken from upstream.
- The 25 PR authors are credited by name and told their work has been picked up.
  That is the main lever for bringing contributors across, `andredezzy` (8 PRs) in
  particular.
