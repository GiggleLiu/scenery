#!/usr/bin/env python3
"""Regenerate site/assets/*.png from the packages' example sources.

Every image on the showcase site is rendered from a committed example under
`<pkg>/examples/`, so the site can never drift from the actual rendered output
again (which is how the SrTiO3 bonds went stale on the site while the README
was fixed). Run via `make site-assets`.

Two kinds of asset:
  * `file`    — render a whole example that already sets an auto-sized page and
                draws a single figure; take page N.
  * `figure`  — a multi-figure example (import-*) draws several figures on one
                default (A4) page, so we render a one-figure wrapper at
                auto page size instead. The wrapper code mirrors that example.
"""

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PPI = "144"  # matches each package's `images` Makefile target

PAGE = '#set page(width: auto, height: auto, margin: 0.4cm)\n'

# One-figure wrappers for the multi-figure import examples. Each mirrors the
# corresponding figure in wyckoff/examples/import-*.typ.
def fig(imports, body):
    return ("figure", "wyckoff",
            f'#import "/lib.typ": {imports}\n{PAGE}{body}\n')

# asset name (site/assets/<name>.png) -> spec
MANIFEST = {
    # wyckoff — crystals & molecules (each example sets an auto page, 1 figure)
    "perovskite":       ("file", "wyckoff", "examples/perovskite.typ", 1),
    "nacl":             ("file", "wyckoff", "examples/nacl.typ", 1),
    "mos2":             ("file", "wyckoff", "examples/mos2.typ", 1),
    "diamond":          ("file", "wyckoff", "examples/diamond.typ", 1),
    "render-modes":     ("file", "wyckoff", "examples/render-modes.typ", 1),
    "perspective":      ("file", "wyckoff", "examples/perspective.typ", 1),
    # file-import figures (rendered one per asset from a wrapper)
    "import-cif-nacl":  fig("import-cif, crystal",
                            '#crystal(import-cif("/examples/data/nacl-ops.cif"), width: 5cm)'),
    "import-poscar-cu": fig("import-poscar, crystal",
                            '#crystal(import-poscar("/examples/data/cu.poscar"), width: 5cm)'),
    "import-xyz-water": fig("import-xyz, molecule",
                            '#molecule(import-xyz("/examples/data/water.xyz"), width: 5cm)'),
    "import-extxyz-si": fig("import-xyz, crystal",
                            '#crystal(import-xyz("/examples/data/si.extxyz"), width: 5cm)'),
    # scenery — engine gallery
    "c60":              ("file", "scenery", "examples/c60.typ", 1),
    "scenery-hero":     ("file", "scenery", "examples/hero.typ", 1),
    "solids":           ("file", "scenery", "examples/solids.typ", 1),
    # brillouin — reciprocal space
    "bz-band":          ("file", "brillouin", "examples/bz-band.typ", 1),
    "fcc-bz":           ("file", "brillouin", "examples/fcc-bz.typ", 1),
}

OUT_DIR = ROOT / "site" / "assets"


def typst() -> str:
    return os.environ.get("TYPST", "typst")


def compile_png(pkg: str, src: Path, out_pattern: Path):
    root = ROOT / pkg
    subprocess.run(
        [typst(), "compile", "--root", str(root),
         "--format", "png", "--ppi", PPI, str(src), str(out_pattern)],
        check=True,
    )


def render_pages(pkg: str, src: Path, tmp: Path) -> list[Path]:
    compile_png(pkg, src, tmp / "page-{p}.png")
    return sorted(tmp.glob("page-*.png"),
                  key=lambda p: int(p.stem.split("-")[1]))


def build(name: str, spec, tmp: Path) -> Path:
    kind = spec[0]
    if kind == "file":
        _, pkg, rel, page = spec
        pages = render_pages(pkg, ROOT / pkg / rel, tmp)
        if page > len(pages):
            raise SystemExit(f"{rel}: wanted page {page}, {len(pages)} rendered")
        return pages[page - 1]
    if kind == "figure":
        _, pkg, code = spec
        # The wrapper must live under the package root so `/lib.typ` resolves.
        wrapper = ROOT / pkg / f".site-{name}.typ"
        wrapper.write_text(code)
        try:
            pages = render_pages(pkg, wrapper, tmp)
        finally:
            wrapper.unlink()
        return pages[0]
    raise SystemExit(f"{name}: unknown spec kind {kind!r}")


def main() -> int:
    only = set(sys.argv[1:])  # optional: regenerate just these asset names
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    n = 0
    for name, spec in MANIFEST.items():
        if only and name not in only:
            continue
        with tempfile.TemporaryDirectory() as td:
            page = build(name, spec, Path(td))
            shutil.copyfile(page, OUT_DIR / f"{name}.png")
        print(f"  {name}.png")
        n += 1
    print(f"Regenerated {n} site asset(s) in {OUT_DIR.relative_to(ROOT)}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
