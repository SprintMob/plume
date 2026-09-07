#!/bin/bash
# The rename left nothing behind, and took nothing it should not have.
#
# A mechanical rename has two predictable failures, and this checks for both.
#
# It renames what must not be renamed. The /tmp log paths are the sharp case:
# those files were written by parrot, the privacy remediation that finds them is
# the whole reason they are still named that, and a plume path there would
# silently stop helping exactly the people migrating. So the first half asserts
# the legacy literals are still *present*.
#
# And it misses something. The second half fails on any parrot left in code, as
# opposed to in a comment: a string, a path, an identifier. Comments are skipped
# on purpose, because after this work almost every comment mentioning parrot is
# there to explain why the line under it was left alone. Three shapes of prose
# are allowed through as well, because they are sentences shown to a person who
# is migrating and the old name is what they are looking for.
#
# Prose is out of scope. README, CONTEXT.md, docs/ and .scratch/ describe the
# fork's history, and that history was called parrot.

set -euo pipefail
cd "$(dirname "$0")/.."

status=0
fail() {
  echo "  ✗ $1" >&2
  status=1
}

# 1. What must still be there.
must_exist() {
  if ! grep -rqF "$1" "$2"; then
    fail "$1 has gone from $2, and it is load-bearing: $3"
  fi
}

must_exist '/tmp/parrot.out.log' Sources \
  "the world-readable logs parrot left behind are found by that exact path"
must_exist '/tmp/parrot.err.log' Sources \
  "same"
must_exist 'com.digimata.parrot' Sources \
  "doctor cannot name the pre-rename launch agent without it"
must_exist 'appendingPathComponent("parrot"' Sources \
  "the migration reads the model weights and the capture cache from there"

# 2. What must not.
#
# Whole files exempted, because they are *about* the old install and every
# mention in them is the subject rather than a leftover.
EXEMPT='^(Sources/plume/Migration\.swift|Tests/plumeTests/MigrationTests\.swift|scripts/check-rename\.sh)'
SCAN=(Sources Tests scripts packaging .github Package.swift)

leftovers=$(
  grep -rn -i parrot "${SCAN[@]}" 2>/dev/null \
    | grep -Ev "$EXEMPT" \
    | grep -Ev ':[0-9]+: *(//|#|\*)' \
    | grep -Ev '/tmp/parrot|com\.digimata\.parrot|Parrot Local Signing|PARROT' \
    | grep -Ev 'parrot install|was parrot|Application Support/parrot' \
    || true
)

if [ -n "$leftovers" ]; then
  echo "parrot survives outside a comment, which a rename should not leave:" >&2
  printf '%s\n' "$leftovers" | sed 's/^/  /' >&2
  echo >&2
  echo "If one of these is deliberate, exempt it in $0 and say why." >&2
  status=1
fi

if [ "$status" -eq 0 ]; then
  echo "✓ the legacy literals are intact and nothing else carries the old name"
else
  exit 1
fi
