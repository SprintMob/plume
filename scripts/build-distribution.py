#!/usr/bin/env python3
"""Render deterministic download copy. No runtime GitHub/API availability probe."""
import argparse
import json
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parent.parent
URL = "https://github.com/SprintMob/plume/releases/latest/download/plume-macos-arm64.dmg"
CLI = "curl -fsSL https://raw.githubusercontent.com/SprintMob/plume/main/scripts/install.sh | sh"


def render(config):
    available = config["dmgAvailable"]
    if not isinstance(available, bool):
        raise ValueError("dmgAvailable must be a boolean")
    if available and not re.fullmatch(r"v\d+\.\d+\.\d+", config.get("stableRelease") or ""):
        raise ValueError("Enable DMG only after recording its published stable vX.Y.Z release")
    if available:
        readme = f"[Download Plume for Mac]({URL})\n\nDownload → drag Plume into Applications → open Plume. Follow the guided setup;\nthe recommended Parakeet TDT v3 model downloads about 461 MB on first use.\n\nRequires macOS 14 or later and Apple Silicon."
        site = f'<a class="command" href="{URL}">Download Plume for Mac</a>\n  <p class="req">macOS 14+ · Apple Silicon. Download, drag Plume into Applications,\n  then open Plume. Guided setup downloads about 461 MB for the recommended model.</p>'
        honesty = '<p>The browser download is a Developer ID-signed, notarized release. The historical v0.1.0 build remains ad hoc; local smoke builds are not notarized.</p>'
    else:
        readme = f"```sh\n{CLI}\n\"$HOME/.local/bin/plume\" setup\n```\n\nThe CLI installer is the live installation path. A signed browser download is\nstaged for a future stable release; it is not available yet. First setup downloads\nabout 461 MB for the recommended Parakeet TDT v3 model. macOS 14+ and Apple Silicon required."
        site = f'<button class="command" id="copy" type="button">\n    <code>{CLI}</code>\n    <span class="hint" id="hint">copy</span>\n  </button>\n  <p class="req">macOS 14+ · Apple Silicon. The recommended speech model downloads\n  about 461 MB on first setup. A signed browser download is not available yet.</p>'
        honesty = '<p>The current v0.1.0 release is ad hoc and is not notarized. A browser download is blocked by Gatekeeper; the CLI installer above remains the supported path. Each ad-hoc update needs a new Accessibility grant. <a href="https://github.com/SprintMob/plume#current-release-signature">Read the details.</a></p>'
    return readme, site, honesty


def replace(text, name, content):
    pattern = rf"<!-- {name}:start -->.*?<!-- {name}:end -->"
    result, count = re.subn(pattern, lambda _: f"<!-- {name}:start -->\n{content}\n<!-- {name}:end -->", text, flags=re.S)
    if count != 1:
        raise ValueError(f"Expected exactly one {name} block")
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=ROOT / "dist/site")
    parser.add_argument("--update-readme", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    readme, download, honesty = render(json.loads((ROOT / "distribution.json").read_text()))
    readme_path = ROOT / "README.md"
    updated = replace(readme_path.read_text(), "download", readme)
    if args.check:
        if updated != readme_path.read_text():
            raise SystemExit("README download copy is stale; run scripts/build-distribution.py --update-readme")
        return
    if args.update_readme:
        readme_path.write_text(updated)
    args.output.mkdir(parents=True, exist_ok=True)
    for path in (ROOT / "site").iterdir():
        if path.is_file():
            shutil.copy2(path, args.output / path.name)
    html = (ROOT / "site/index.html").read_text()
    html = replace(replace(html, "download", download), "signature", honesty)
    (args.output / "index.html").write_text(html)
    shutil.copy2(ROOT / "scripts/install.sh", args.output / "install.sh")


if __name__ == "__main__":
    main()
