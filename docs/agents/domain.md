# Domain Docs

How the engineering skills should consume this repo's domain documentation when
exploring the codebase.

**Layout: single-context.** One `CONTEXT.md` and one `docs/adr/` at the repo
root, covering the whole project. This is not a monorepo, so there is no
`CONTEXT-MAP.md` and no per-context `src/<context>/docs/adr/`.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root.
- **`docs/adr/`**: read ADRs that touch the area you're about to work in.

If any of these files don't exist, **proceed silently**. Don't flag their
absence; don't suggest creating them upfront. The `/domain-modeling` skill
(reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates
them lazily when terms or decisions actually get resolved.

Both exist as of 2026-08-20: `CONTEXT.md` holds the glossary, and `docs/adr/`
holds ADR-0001 (why this repo is a fork of `digimata/parrot`) and ADR-0002 (why
upstream PRs are merged in waves ordered by conflict surface). Read both before
touching the merge queue — they explain why almost no code here is ours.

## File structure

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-....md
│   └── 0002-....md
└── src/
```

`docs/agents/` (this file) sits outside that structure — it configures the
skills rather than describing the domain.

If this repo ever splits into packages, promote the root `CONTEXT.md` to a
`CONTEXT-MAP.md` pointing at one `CONTEXT.md` per context, and re-read this file.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal,
a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift
to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either
you're inventing language the project doesn't use (reconsider) or there's a real
gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than
silently overriding:

> _Contradicts ADR-0007 (event-sourced orders), but worth reopening because…_
