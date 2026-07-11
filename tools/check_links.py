#!/usr/bin/env python3
"""Check that every relative link/image in the repo's markdown files resolves.

Scans markdown links `[..](path)`, images `![..](path)`, and HTML `src="path"` /
`href="path"` attributes in every tracked *.md file. Absolute URLs and pure
anchors are skipped; `path#anchor` is checked as `path`. Exits non-zero listing
each broken reference.
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)|(?:src|href)=\"([^\"]+)\"")
SKIP = ("http://", "https://", "mailto:", "#")

files = subprocess.run(
    ["git", "ls-files", "*.md"], cwd=ROOT, capture_output=True, text=True, check=True
).stdout.split()

broken = []
for md in files:
    md_path = ROOT / md
    for m in LINK.finditer(md_path.read_text()):
        target = m.group(1) or m.group(2)
        if target.startswith(SKIP):
            continue
        rel = target.split("#", 1)[0]
        if not rel:
            continue
        if not (md_path.parent / rel).exists():
            broken.append(f"{md}: {target}")

if broken:
    print("Broken relative links:")
    print("\n".join(f"  {b}" for b in broken))
    sys.exit(1)
print(f"check-links: {len(files)} markdown files OK")
