# Contributing

Plume takes contributions. Before you spend an evening on one, two things about
this repo that are not standard.

## Most of this code came from people who never got a review

Plume is a fork of [`digimata/parrot`](https://github.com/digimata/parrot).
Upstream stopped taking commits in May 2026 with 25 open pull requests, and this
fork merged 16 of them. The people who wrote them were not asked and were not
involved. [NOTICE](NOTICE) names them.

That history is why review here is not a formality. A patch that sits unread for
four months is the thing this project exists downstream of.

## Decisions live in the repo, not in issue threads

There is no external tracker. Two conventions carry everything:

- **`.scratch/<feature-slug>/spec.md`** is where a piece of work is specified
  before it is built: the symptom, what was decided, what was deliberately left
  out, and how it was verified. One directory per feature, one commit per
  feature, each commit building on its own.
- **`docs/adr/NNNN-*.md`** is where a decision that outlives its feature is
  argued. An ADR states the alternative it rejected and why, and has a
  `## Consequences` section that includes the ones that hurt. ADR-0008 is the
  example to copy: it says plainly which of its own claims turned out to be
  wrong.

`CONTEXT.md` is the glossary. If you find yourself explaining what a word means
in a pull request, it belongs there instead.

## What a good pull request looks like

1. **One feature, one commit**, and that commit builds and tests on its own.
   `.github/workflows/test.yml` checks this, which is newer than the convention
   and is what makes it real rather than aspirational.
2. **A `.scratch/<slug>/spec.md`** for anything past a typo, written before the
   code where possible.
3. **The commit message argues.** Look at `git log`. Messages here say what the
   old behaviour was, why it was wrong, and what was rejected. "Fix overlay bug"
   is not one of them.
4. **Tests where they are honest.** This repo does not test UI, on purpose, and
   that is not going to change on a pull request. Everything else is testable:
   state machines, path resolution, migration, contrast ratios. Where a test
   would need to touch the machine's launchd session or keychain, inject a seam
   instead, the way `Migration` does.
5. **No em dashes in user-visible strings.** Short sentences, one idea each,
   numbers before promises, no "Oops!". `scripts/check-rename.sh` and
   `StyleContrastTests` enforce the two rules that can be enforced.

## Running it

```sh
swift build -c release
swift test
./scripts/bundle.sh              # dist/Plume.app, ad-hoc signed
```

`./scripts/install-local.sh` builds, signs with a local certificate and installs
to `~/Applications`. Read its header first: the certificate is what keeps macOS
from revoking Accessibility on every rebuild, and the script refuses to install
a signature that would not survive.

## What is out of scope

`docs/architecture.md` has a non-goals list and it is meant seriously. Cloud
transcription, AI post-processing, diarization, cross-platform. A pull request
adding one of those will be turned down whatever its quality, and it is fairer
to say so here than after you have written it.
