#!/bin/bash
# Regenerate THIRD-PARTY.md from the resolved dependencies.
#
# This is an obligation, not a courtesy. swift-argument-parser and FluidAudio
# are Apache-2.0, whose section 4 requires the licence and any NOTICE to travel
# with distributions "in Source or Object form". The moment a statically linked
# binary ships, that attaches to the binary, and every release before this one
# went out without it.
#
# Run it after changing Package.swift or Package.resolved. It reads the licence
# files out of .build/checkouts, so `swift build` has to have run.

set -euo pipefail
cd "$(dirname "$0")/.."

CHECKOUTS=".build/checkouts"
OUT="THIRD-PARTY.md"

for dir in argmax-oss-swift FluidAudio swift-argument-parser; do
    [ -d "$CHECKOUTS/$dir" ] || {
        echo "$CHECKOUTS/$dir is missing; run swift build first" >&2
        exit 1
    }
done

version() {
    python3 - "$1" <<'PY'
import json, sys
identity = sys.argv[1]
pins = json.load(open("Package.resolved"))["pins"]
for pin in pins:
    if pin["identity"] == identity:
        state = pin["state"]
        print(state.get("version") or state["revision"][:12])
        break
else:
    print("unknown")
PY
}

{
cat <<EOF
# Third-party components

Plume links the components below statically into the executable inside
\`Plume.app\`. This file is their attribution, and it ships inside the app as
\`Contents/Resources/ACKNOWLEDGEMENTS.txt\`.

Two of the three are Apache-2.0, whose section 4 requires the licence and any
NOTICE to travel with distributions in source **or object** form. A statically
linked binary is object form, so the obligation attaches to the release
artefact and not only to this repository.

Regenerate with \`./scripts/third-party.sh\`. Do not hand-edit.

| Component | Version | Licence | Copyright |
|---|---|---|---|
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | $(version swift-argument-parser) | Apache-2.0 | The Swift project authors |
| [argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift) (WhisperKit) | $(version argmax-oss-swift) | MIT | (c) 2024 argmax, inc. |
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | $(version fluidaudio) | Apache-2.0 | FluidInference |

argmax-oss-swift vendors code derived from
[swift-transformers](https://github.com/huggingface/swift-transformers)
(Apache-2.0, Copyright 2022 Hugging Face SAS) under
\`Sources/ArgmaxCore/External\`. Its NOTICES file is reproduced in full below,
which is what Apache-2.0 section 4(d) asks for.

---

## argmax-oss-swift, MIT

\`\`\`
EOF
cat "$CHECKOUTS/argmax-oss-swift/LICENSE"
cat <<'EOF'
```

## argmax-oss-swift, NOTICES

```
EOF
cat "$CHECKOUTS/argmax-oss-swift/NOTICES"
cat <<'EOF'
```

## swift-argument-parser and FluidAudio, Apache License 2.0

Both are distributed under the identical, unmodified Apache License 2.0,
reproduced once below.

```
EOF
cat "$CHECKOUTS/swift-argument-parser/LICENSE.txt"
cat <<'EOF'
```
EOF
} > "$OUT"

echo "wrote $OUT ($(wc -l < "$OUT") lines)"
