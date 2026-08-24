# Merge upstream PRs in waves ordered by conflict surface

`Sources/parrot/Parrot.swift` is touched by 17 of the 25 open PRs, and eight other
files by five or more, so the merge order — not the value of any single PR —
decides the total cost of the work. The PRs are grouped into five waves ordered by
how much rebasing each forces on the ones after it: wave 1 is atomic and
conflict-free, wave 5 is #26 alone, which conflicts with nine other PRs.

Merging in order of interest instead would mean paying for the same rebases several
times over. The one deliberate exception is the privacy fix (#9, first commit),
cherry-picked into wave 1 out of order because it stops the full text of every
dictation being written to a world-readable log.

Per-PR wave assignment, dependencies and conflict risks are on the triage board:
https://claude.ai/code/artifact/72aebb8a-a617-4aa1-a851-b27e48be1823

## Consequences

- Two arbitrations were open and gated the plan: whether #26 (4,256 lines,
  conflicting with nine PRs) becomes the fork's base or is closed, and which of
  #4/#7/#10/#18 is the base for the hotkey cluster. The second is settled — see
  [ADR-0003](./0003-hotkey-cluster-base.md). The first is still open.
- #26 must be settled immediately after wave 1. Every merge landed before that
  decision makes it more expensive, and it is the only irreversible one.
