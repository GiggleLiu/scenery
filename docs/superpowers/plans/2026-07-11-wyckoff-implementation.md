# wyckoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A pure-Typst Universe package `wyckoff` that renders Materials Project–style crystal figures from symmetry-native input (230 space groups + 80 layer groups, Wyckoff positions), per the approved spec at `docs/superpowers/specs/2026-07-11-wyckoff-crystal-visualization-design.md`.

**Architecture:** Offline Python generators (pyxtal/pymatgen) emit JSON data (group ops, Wyckoff tables, element colors/radii). A pure-Typst engine expands symmetry orbits, builds geometry (boundary images, supercells, bonds, coordination polyhedra), projects orthographically, and a CeTZ renderer draws depth-sorted primitives. Hard data boundary between engine and renderer (plugin-ready).

**Tech Stack:** Typst ≥0.14, cetz 0.5.2 (only runtime dep). Dev tools: Python 3.11 venv with pyxtal, pymatgen, spglib, numpy.

## Global Constraints

- Repo root: `/Users/liujinguo/tcode/wyckoff` (git repo already initialized; spec is committed).
- **Before writing ANY Typst rendering or library code, read the local cetz clone `~/tcode/cetz` for best practices** — at minimum: `src/vector.typ`, `src/matrix.typ`, `src/styles.typ`, `src/draw/shapes.typ`, `gallery/`, and skim `src/lib.typ` for module organization. Reuse cetz idioms; do not reinvent what cetz provides in the renderer. (Spec requirement.)
- Typst compiler floor: `0.14.0`. CeTZ pinned: `@preview/cetz:0.5.2`.
- All test files live in `tests/`, compile with `typst compile --root . tests/<name>.typ /tmp/out.pdf`, and use `assert(...)` — compile success = pass (same pattern as `~/tcode/periodic-table`).
- Python tooling runs ONLY inside `tools/.venv` (the anaconda base env has a broken numpy/pyarrow mix — never use it).
- Generated JSON in `data/` and `tests/fixtures/` is committed; CI never runs Python.
- Units: fractional coordinates for space groups; for layer groups x,y fractional and z in Å. Lengths in Å, angles accepted as Typst `angle` or plain number-in-degrees.
- Every commit message ends with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Commit after every green task. No placeholder code, no dead options.

## File Structure (final)

```
wyckoff/
  typst.toml  LICENSE  README.md  Makefile  .gitignore
  lib.typ                    # entrypoint: re-exports public API
  src/
    linalg.typ               # 3-vector / 3x3-matrix helpers (engine-side, no cetz)
    data.typ                 # JSON loading, element lookup
    lattice.typ              # lattice params -> vectors, per-system validation
    symmetry.typ             # orbit expansion (the `expand` boundary)
    structure.typ            # public structure() constructor + validation
    geometry.typ             # boundary images, supercell, bonds, polyhedra hull
    project.typ              # view rotation + orthographic projection
    scene.typ                # structure + options -> depth-keyed primitive list
    render.typ               # cetz drawing (spheres/bonds/faces/edges/legend/axes)
    prototypes.typ           # named prototype structures
  data/
    spacegroups.json  layergroups.json  elements.json
  tools/
    requirements.txt  gen_elements.py  gen_groups.py  gen_fixtures.py
  tests/
    fixtures/*.json
    test-data.typ  test-linalg.typ  test-lattice.typ  test-symmetry.typ
    test-structure.typ  test-geometry.typ  test-scene.typ
    test-render.typ  test-prototypes.typ
  examples/
    nacl.typ  perovskite.typ  diamond.typ  mos2.typ  gallery.typ
  .github/workflows/ci.yml
```

---

### Task 1: Repo scaffold + tools venv

**Files:**
- Create: `typst.toml`, `LICENSE` (MIT), `.gitignore`, `Makefile`, `lib.typ`, `tools/requirements.txt`
- Test: smoke-compile of `lib.typ`

**Interfaces:**
- Produces: `make test` harness (runs every `tests/test-*.typ`); `tools/.venv` for all later Python steps.

- [ ] **Step 1: Write scaffold files**

`typst.toml`:
```toml
[package]
name = "wyckoff"
version = "0.1.0"
entrypoint = "lib.typ"
authors = ["GiggleLiu"]
license = "MIT"
description = "Materials Project style crystal structure figures from space groups, layer groups and Wyckoff positions"
repository = "https://github.com/GiggleLiu/wyckoff"
keywords = ["crystal", "crystallography", "space group", "wyckoff", "materials", "visualization", "physics", "chemistry"]
categories = ["visualization"]
compiler = "0.14.0"
exclude = ["docs/*", "tools/*", "tests/*", "examples/*", "images/*", "Makefile", ".github/*"]
```

`.gitignore`:
```
tools/.venv/
tests/*.pdf
tests/*.png
examples/*.pdf
*.pdf
!manual.pdf
__pycache__/
```

`LICENSE`: standard MIT text, copyright 2026 GiggleLiu.

`Makefile`:
```makefile
.PHONY: all test data fixtures images clean venv

TYPST = typst compile --root .
TESTS := $(wildcard tests/test-*.typ)
VENV = tools/.venv/bin/python

all: test

test:
	@for t in $(TESTS); do \
	  echo "== $$t"; \
	  $(TYPST) $$t $${t%.typ}.pdf || exit 1; \
	done
	@echo "All tests passed!"

venv:
	python3 -m venv tools/.venv
	tools/.venv/bin/pip install -r tools/requirements.txt

data:
	$(VENV) tools/gen_elements.py
	$(VENV) tools/gen_groups.py

fixtures:
	$(VENV) tools/gen_fixtures.py

images:
	@for f in examples/*.typ; do $(TYPST) $$f images/$$(basename $${f%.typ}).png; done

clean:
	rm -f tests/*.pdf examples/*.pdf
```

`lib.typ` (stub for now):
```typst
#let wyckoff-version = version(0, 1, 0)
```

`tools/requirements.txt`:
```
numpy
spglib
pymatgen
pyxtal
```

- [ ] **Step 2: Verify the stub compiles and the venv builds**

Run:
```bash
cd /Users/liujinguo/tcode/wyckoff
echo '#import "/lib.typ": wyckoff-version
#wyckoff-version' > tests/test-smoke.typ
typst compile --root . tests/test-smoke.typ tests/test-smoke.pdf
make venv
tools/.venv/bin/python -c "from pyxtal.symmetry import Group; print(Group(225).symbol)"
```
Expected: compile succeeds; last line prints `Fm-3m` (numpy-1.x warnings from transitive imports are acceptable only if the command still succeeds; in a fresh venv there should be none). Delete `tests/test-smoke.typ` and its pdf afterwards — Task 2 adds real tests.

- [ ] **Step 3: Commit**
```bash
git add -A && git commit -m "Scaffold package: typst.toml, Makefile, tools venv"
```

---

### Task 2: Element data (`gen_elements.py` → `data/elements.json` → `src/data.typ`)

**Files:**
- Create: `tools/gen_elements.py`, `data/elements.json` (generated), `src/data.typ`
- Test: `tests/test-data.typ`

**Interfaces:**
- Produces: `data.typ`: `element-info(symbol) -> (color: rgb, color-vesta: rgb, r-cov: float, r-atom: float)`; panics with a clear message for unknown symbols. Also `sg-table` and `lg-table` loaders added in Task 3.

- [ ] **Step 1: Write the failing test**

`tests/test-data.typ`:
```typst
#import "/src/data.typ": element-info

#let na = element-info("Na")
#assert(na.r-cov > 1.5 and na.r-cov < 1.8, message: "Na covalent radius ~1.66")
#assert(type(na.color) == color, message: "color must be a Typst color")
#let o = element-info("O")
#assert(o.r-cov < 0.8, message: "O covalent radius ~0.66")
#assert(element-info("Ti").r-atom > 1.0)
Data OK
```

- [ ] **Step 2: Run test to verify it fails**

Run: `typst compile --root . tests/test-data.typ tests/test-data.pdf`
Expected: FAIL — `file not found` for `src/data.typ`.

- [ ] **Step 3: Write the generator and run it**

`tools/gen_elements.py`:
```python
"""Generate data/elements.json: Jmol/VESTA colors + covalent/atomic radii per element."""
import json
from pathlib import Path

from pymatgen.core.periodic_table import Element
from pymatgen.analysis.local_env import CovalentRadius
from pymatgen.vis.structure_vtk import EL_COLORS

OUT = Path(__file__).resolve().parent.parent / "data" / "elements.json"

def hexcolor(rgb):
    return "#{:02X}{:02X}{:02X}".format(*rgb)

data = {}
for el in Element:
    sym = el.symbol
    r_cov = CovalentRadius.radius.get(sym)
    r_atom = float(el.atomic_radius) if el.atomic_radius is not None else None
    if r_cov is None and r_atom is None:
        continue  # exotic elements without any radius data
    data[sym] = {
        "color": hexcolor(EL_COLORS["Jmol"].get(sym, (128, 128, 128))),
        "color-vesta": hexcolor(EL_COLORS["VESTA"].get(sym, (128, 128, 128))),
        "r-cov": round(r_cov if r_cov is not None else r_atom, 3),
        "r-atom": round(r_atom if r_atom is not None else r_cov, 3),
    }

assert len(data) > 90, f"only {len(data)} elements"
assert abs(data["O"]["r-cov"] - 0.66) < 0.05
OUT.parent.mkdir(exist_ok=True)
OUT.write_text(json.dumps(data, indent=1, sort_keys=True))
print(f"wrote {OUT} ({len(data)} elements)")
```

Run: `mkdir -p data && tools/.venv/bin/python tools/gen_elements.py`
Expected: `wrote .../data/elements.json (9X elements)`.

- [ ] **Step 4: Write `src/data.typ`**

```typst
// Element and symmetry-group data access.
#let _elements = json("/data/elements.json")

#let element-info(symbol) = {
  assert(
    symbol in _elements,
    message: "wyckoff: unknown element '" + symbol + "'",
  )
  let e = _elements.at(symbol)
  (
    color: rgb(e.color),
    color-vesta: rgb(e.color-vesta),
    r-cov: e.r-cov,
    r-atom: e.r-atom,
  )
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `typst compile --root . tests/test-data.typ tests/test-data.pdf`
Expected: PASS.

- [ ] **Step 6: Commit**
```bash
git add -A && git commit -m "Add element data (Jmol/VESTA colors, radii) and data.typ accessor"
```

---

### Task 3: Group data generator (`gen_groups.py` → `spacegroups.json` + `layergroups.json`)

**Files:**
- Create: `tools/gen_groups.py`, `data/spacegroups.json`, `data/layergroups.json`
- Modify: `src/data.typ`
- Test: extend `tests/test-data.typ`

**Interfaces:**
- Produces JSON schema consumed by Tasks 5–7. Per group number (string key):
  - `symbol`: str (e.g. `"Fm-3m"`)
  - `ltype`: one of `triclinic|monoclinic|orthorhombic|tetragonal|trigonal|hexagonal|cubic` (3D) or `oblique|rectangular|square|hexagonal2d` (layer)
  - `ops`: array of `[R, t]` with `R` 3×3 nested array, `t` length-3 array — the FULL general position incl. centering translations
  - `wyckoff`: dict letter → `(mult: int, vars: array of "x"/"y"/"z", m: 3×3, t: 3)` where the site representative is `m·(x,y,z) + t`
- `data.typ` gains: `group-data(kind, number)` with `kind: "3d" | "layer"`, panicking on out-of-range numbers.

- [ ] **Step 1: Write the failing test (extend `tests/test-data.typ`)**

Append:
```typst
#import "/src/data.typ": group-data

#let sg225 = group-data("3d", 225)
#assert(sg225.symbol == "Fm-3m")
#assert(sg225.ops.len() == 192, message: "Fm-3m has 192 ops incl. centering")
#assert(sg225.wyckoff.a.mult == 4)
#assert(sg225.wyckoff.a.vars == ())
#assert(sg225.ltype == "cubic")

#let lg78 = group-data("layer", 78)
#assert(lg78.symbol.contains("6"), message: "LG 78 is p-6m2")
#assert(lg78.ltype == "hexagonal2d")
#assert(group-data("3d", 1).ops.len() == 1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `typst compile --root . tests/test-data.typ tests/test-data.pdf`
Expected: FAIL — `group-data` not found.

- [ ] **Step 3: Write the generator**

`tools/gen_groups.py`:
```python
"""Generate data/spacegroups.json (230 groups) and data/layergroups.json (80 layer groups).

Source: pyxtal.symmetry.Group (Bilbao-derived tables, standard ITA settings,
conventional cells; trigonal R groups in hexagonal setting).

Self-checks performed here (so the Typst side can trust the data):
  1. Orbit of each Wyckoff representative under `ops` has size == multiplicity.
  2. Every op leaves the lattice metric invariant for the group's lattice type.
  3. Layer-group ops never mix z with x,y and have zero z-translation.
"""
import json
from fractions import Fraction
from pathlib import Path

import numpy as np
from pyxtal.symmetry import Group

DATA = Path(__file__).resolve().parent.parent / "data"

def ltype_3d(n):
    if n <= 2: return "triclinic"
    if n <= 15: return "monoclinic"
    if n <= 74: return "orthorhombic"
    if n <= 142: return "tetragonal"
    if n <= 167: return "trigonal"
    if n <= 194: return "hexagonal"
    return "cubic"

def ltype_layer(n):
    # ITA Vol. E: 1-7 oblique, 8-48 rectangular, 49-64 square, 65-80 hexagonal
    if n <= 7: return "oblique"
    if n <= 48: return "rectangular"
    if n <= 64: return "square"
    return "hexagonal2d"

# Representative metric tensors per lattice type (arbitrary but generic values)
def metric(ltype):
    import math
    def cell(a, b, c, al, be, ga):
        al, be, ga = map(math.radians, (al, be, ga))
        av = np.array([a, 0, 0])
        bv = np.array([b*math.cos(ga), b*math.sin(ga), 0])
        cx = c*math.cos(be)
        cy = c*(math.cos(al) - math.cos(be)*math.cos(ga))/math.sin(ga)
        cz = math.sqrt(max(c*c - cx*cx - cy*cy, 0))
        cv = np.array([cx, cy, cz])
        L = np.vstack([av, bv, cv])
        return L @ L.T
    return {
        "triclinic":    cell(3.1, 4.3, 5.7, 81, 94, 103),
        "monoclinic":   cell(3.1, 4.3, 5.7, 90, 104, 90),
        "orthorhombic": cell(3.1, 4.3, 5.7, 90, 90, 90),
        "tetragonal":   cell(3.1, 3.1, 5.7, 90, 90, 90),
        "trigonal":     cell(3.1, 3.1, 5.7, 90, 90, 120),
        "hexagonal":    cell(3.1, 3.1, 5.7, 90, 90, 120),
        "cubic":        cell(3.1, 3.1, 3.1, 90, 90, 90),
        "oblique":      cell(3.1, 4.3, 1.0, 90, 90, 103),
        "rectangular":  cell(3.1, 4.3, 1.0, 90, 90, 90),
        "square":       cell(3.1, 3.1, 1.0, 90, 90, 90),
        "hexagonal2d":  cell(3.1, 3.1, 1.0, 90, 90, 120),
    }[ltype]

def frac_round(x):
    """Snap float translations/matrix entries to exact simple fractions."""
    f = Fraction(x).limit_denominator(12)
    assert abs(float(f) - x) < 1e-8, f"non-fractional entry {x}"
    return float(f)

def encode_op(affine):
    R = [[frac_round(affine[i][j]) for j in range(3)] for i in range(3)]
    t = [frac_round(affine[i][3]) % 1.0 for i in range(3)]
    return [R, t]

def wrap(v, periodic):
    return np.where(periodic, v % 1.0, v)

def orbit_size(ops, rep, periodic, tol=1e-5):
    pts = []
    for R, t in ops:
        q = wrap(np.array(R) @ rep + np.array(t), periodic)
        if not any(np.all(np.abs(np.minimum(np.abs(q-p), np.where(periodic, 1-np.abs(q-p), np.inf))) < tol) for p in pts):
            pts.append(q)
    return len(pts)

def build(dim, count, ltype_fn, out_name):
    periodic = np.array([True, True, dim == 3])
    result = {}
    for n in range(1, count + 1):
        g = Group(n, dim=dim)
        lt = ltype_fn(n)
        gen_wp = g.Wyckoff_positions[0]           # general position = all group elements
        ops = [encode_op(op.affine_matrix) for op in gen_wp.ops]
        # check 2: metric invariance
        G = metric(lt)
        for R, t in ops:
            Rm = np.array(R)
            assert np.allclose(Rm.T @ G @ Rm, G, atol=1e-6), f"group {n} ({dim}D): op breaks {lt} metric"
            if dim == 2:  # check 3: layer safety
                assert abs(abs(Rm[2][2]) - 1) < 1e-9 and abs(Rm[2][0]) < 1e-9 and abs(Rm[2][1]) < 1e-9
                assert abs(Rm[0][2]) < 1e-9 and abs(Rm[1][2]) < 1e-9 and abs(t[2]) < 1e-9
        wyckoff = {}
        for wp in g.Wyckoff_positions:
            aff = wp.ops[0].affine_matrix
            m = [[frac_round(aff[i][j]) for j in range(3)] for i in range(3)]
            t = [frac_round(aff[i][3]) % 1.0 for i in range(3)]
            vars_ = [v for j, v in enumerate("xyz") if any(abs(m[i][j]) > 1e-9 for i in range(3))]
            letter = wp.get_label()  # e.g. "192l"
            letter = "".join(ch for ch in letter if ch.isalpha())
            # check 1: multiplicity via orbit of a generic representative
            p = np.array(m) @ np.array([0.1234, 0.2618, 0.3711]) + np.array(t)
            npts = orbit_size([(np.array(R), np.array(tt)) for R, tt in ops], p, periodic)
            assert npts == wp.multiplicity, \
                f"group {n} ({dim}D) wyckoff {letter}: orbit {npts} != mult {wp.multiplicity}"
            wyckoff[letter] = {"mult": wp.multiplicity, "vars": vars_, "m": m, "t": t}
        result[str(n)] = {"symbol": g.symbol, "ltype": lt, "ops": ops, "wyckoff": wyckoff}
        if n % 40 == 0:
            print(f"  {dim}D group {n}/{count}")
    out = DATA / out_name
    out.write_text(json.dumps(result, separators=(",", ":")))
    print(f"wrote {out} ({out.stat().st_size // 1024} KB)")

build(3, 230, ltype_3d, "spacegroups.json")
build(2, 80, ltype_layer, "layergroups.json")
```

Implementation notes for this step (read before running):
- If pyxtal's general-position op count disagrees with the checks, inspect `Group(n).Wyckoff_positions[0].ops` interactively — for centered groups it must include centering translations (192 for Fm-3m). If it holds only the coset representatives (48), multiply with `g.wyc_sets` / use `wp.get_all_positions` equivalents and re-verify — the metric and multiplicity self-checks will catch either mistake.
- If a generic representative accidentally lands on a special position for some Wyckoff site (orbit < mult), perturb the generic vector for that site (e.g. `[0.1357, 0.2791, 0.4123]`) — but investigate first; it usually means the `m` matrix was encoded wrongly.
- `frac_round` assertion failures on trigonal/hexagonal groups would mean non-fractional matrix entries in the hexagonal basis — they must all still be integers/simple fractions in crystal axes; investigate rather than loosening the tolerance.

Run: `tools/.venv/bin/python tools/gen_groups.py`
Expected: progress lines, then `wrote .../spacegroups.json (~600-1500 KB)` and `wrote .../layergroups.json (...)`, no assertion errors. **The multiplicity self-check across all 230+80 groups is the spec's "universal multiplicity check" — it runs at generation time.**

- [ ] **Step 4: Extend `src/data.typ`**

Append:
```typst
#let _sg = json("/data/spacegroups.json")
#let _lg = json("/data/layergroups.json")

#let group-data(kind, number) = {
  let (table, max, name) = if kind == "3d" { (_sg, 230, "space group") } else { (_lg, 80, "layer group") }
  assert(
    type(number) == int and number >= 1 and number <= max,
    message: "wyckoff: " + name + " number must be 1.." + str(max) + ", got " + repr(number),
  )
  table.at(str(number))
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `typst compile --root . tests/test-data.typ tests/test-data.pdf`
Expected: PASS. If the LG 78 symbol assertion fails, print the actual symbol (`#lg78.symbol`) — pyxtal may spell it `p-6m2` or `P-6m2`; adjust the assertion to the actual spelling, not the data.

- [ ] **Step 6: Commit**
```bash
git add -A && git commit -m "Generate and load symmetry tables for 230 space groups and 80 layer groups"
```

---

### Task 4: Engine linear algebra (`src/linalg.typ`)

**Files:**
- Create: `src/linalg.typ`
- Test: `tests/test-linalg.typ`

**Interfaces:**
- Produces (all take/return plain arrays; no cetz dependency — engine must stay renderer-free):
  `vadd(a,b)`, `vsub(a,b)`, `vscale(a,s)`, `vdot(a,b)`, `vcross(a,b)`, `vlen(a)`, `vnorm(a)`, `mvec(M, v)` (3×3 · 3), `lerp(a,b,t)`.

Read `~/tcode/cetz/src/vector.typ` and `~/tcode/cetz/src/matrix.typ` first for naming/style conventions (short names, pure functions, no content) — but implement locally; the engine must not import cetz.

- [ ] **Step 1: Write the failing test**

`tests/test-linalg.typ`:
```typst
#import "/src/linalg.typ": *

#assert(vadd((1,2,3), (4,5,6)) == (5,7,9))
#assert(vsub((4,5,6), (1,2,3)) == (3,3,3))
#assert(vdot((1,2,3), (4,5,6)) == 32)
#assert(vcross((1,0,0), (0,1,0)) == (0,0,1))
#assert(calc.abs(vlen((3,4,0)) - 5) < 1e-9)
#assert(vnorm((0,0,2)) == (0,0,1))
#assert(mvec(((1,0,0),(0,0,-1),(0,1,0)), (1,2,3)) == (1,-3,2))
#assert(lerp((0,0,0), (2,4,6), 0.5) == (1,2,3))
Linalg OK
```

- [ ] **Step 2: Run test to verify it fails**
Run: `typst compile --root . tests/test-linalg.typ tests/test-linalg.pdf` — Expected: FAIL, file not found.

- [ ] **Step 3: Implement `src/linalg.typ`**

```typst
// Minimal 3-vector / 3x3-matrix helpers for the symmetry engine.
// Plain arrays only; deliberately cetz-free so the engine has no renderer deps.
#let vadd(a, b) = a.zip(b).map(((x, y)) => x + y)
#let vsub(a, b) = a.zip(b).map(((x, y)) => x - y)
#let vscale(a, s) = a.map(x => x * s)
#let vdot(a, b) = a.zip(b).map(((x, y)) => x * y).sum()
#let vcross(a, b) = (
  a.at(1) * b.at(2) - a.at(2) * b.at(1),
  a.at(2) * b.at(0) - a.at(0) * b.at(2),
  a.at(0) * b.at(1) - a.at(1) * b.at(0),
)
#let vlen(a) = calc.sqrt(vdot(a, a))
#let vnorm(a) = vscale(a, 1 / vlen(a))
#let mvec(m, v) = m.map(row => vdot(row, v))
#let lerp(a, b, t) = vadd(vscale(a, 1 - t), vscale(b, t))
```

- [ ] **Step 4: Run test to verify it passes** — same command, Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add -A && git commit -m "Add engine linear algebra helpers"
```

---

### Task 5: Lattice module (`src/lattice.typ`)

**Files:**
- Create: `src/lattice.typ`
- Test: `tests/test-lattice.typ`

**Interfaces:**
- Consumes: `linalg.typ`.
- Produces:
  - `lattice-params(ltype, given) -> (a, b, c, alpha, beta, gamma)` — floats, degrees; validates that `given` (a dict) provides exactly the free parameters of `ltype` (see table below), fills constrained ones. For 2D ltypes `c` is returned as `1.0` and never used.
  - `lattice-vectors(params) -> ((ax,ay,az),(bx,by,bz),(cx,cy,cz))`
  - `frac-to-cart(vecs, frac, periodic) -> (x,y,z)` — for `periodic == (true,true,false)` the z component of `frac` is already Å and passes through.
  - `check-lattice-args(ltype, given) -> (ok: bool, msg: str)` — pure validator so tests can exercise failures without aborting compilation; `lattice-params` asserts on it.

Free parameters: triclinic `a,b,c,alpha,beta,gamma`; monoclinic `a,b,c,beta`; orthorhombic `a,b,c`; tetragonal `a,c`; trigonal/hexagonal `a,c` (γ=120); cubic `a`; oblique `a,b,gamma`; rectangular `a,b`; square `a`; hexagonal2d `a` (γ=120).

- [ ] **Step 1: Write the failing test**

`tests/test-lattice.typ`:
```typst
#import "/src/lattice.typ": *

// cubic: only a; all vectors orthogonal
#let p = lattice-params("cubic", (a: 5.64))
#assert(p.b == 5.64 and p.c == 5.64 and p.gamma == 90.0)
#let v = lattice-vectors(p)
#assert(v.at(0) == (5.64, 0.0, 0.0))
#assert(calc.abs(v.at(2).at(2) - 5.64) < 1e-9)

// hexagonal: gamma filled as 120
#let ph = lattice-params("hexagonal", (a: 3.16, c: 12.3))
#assert(ph.gamma == 120.0)
#let vh = lattice-vectors(ph)
#assert(calc.abs(vh.at(1).at(0) - (-1.58)) < 0.01, message: "b_x = a cos120")

// angles may be typst angles
#let pm = lattice-params("monoclinic", (a: 5.1, b: 5.2, c: 5.3, beta: 99.2deg))
#assert(calc.abs(pm.beta - 99.2) < 1e-9)

// layer/hexagonal2d: only a; frac-to-cart passes z through in angstrom
#let p2 = lattice-params("hexagonal2d", (a: 3.16))
#let v2 = lattice-vectors(p2)
#let cart = frac-to-cart(v2, (1.0/3.0, 2.0/3.0, 1.56), (true, true, false))
#assert(calc.abs(cart.at(2) - 1.56) < 1e-9)

// validation is testable without a panic
#assert(not check-lattice-args("cubic", (a: 5.6, b: 5.6)).ok)
#assert(not check-lattice-args("tetragonal", (a: 5.6)).ok)
#assert(check-lattice-args("triclinic", (a: 1, b: 2, c: 3, alpha: 80, beta: 95, gamma: 103)).ok)
Lattice OK
```

- [ ] **Step 2: Run test to verify it fails** — Expected: FAIL, file not found.

- [ ] **Step 3: Implement `src/lattice.typ`**

```typst
#import "linalg.typ": vscale, vadd

#let _free-params = (
  triclinic: ("a", "b", "c", "alpha", "beta", "gamma"),
  monoclinic: ("a", "b", "c", "beta"),
  orthorhombic: ("a", "b", "c"),
  tetragonal: ("a", "c"),
  trigonal: ("a", "c"),
  hexagonal: ("a", "c"),
  cubic: ("a",),
  oblique: ("a", "b", "gamma"),
  rectangular: ("a", "b"),
  square: ("a",),
  hexagonal2d: ("a",),
)

#let _deg(x) = if type(x) == angle { x / 1deg } else { float(x) }

#let check-lattice-args(ltype, given) = {
  let free = _free-params.at(ltype)
  for k in given.keys() {
    if k not in free {
      return (ok: false, msg: "lattice parameter '" + k + "' is fixed by the " + ltype + " system; give only " + free.join(", "))
    }
  }
  for k in free {
    if k not in given {
      return (ok: false, msg: "the " + ltype + " system requires lattice parameter '" + k + "'")
    }
  }
  (ok: true, msg: "")
}

#let lattice-params(ltype, given) = {
  let chk = check-lattice-args(ltype, given)
  assert(chk.ok, message: "wyckoff: " + chk.msg)
  let g(k, d) = if k in given { _deg(given.at(k)) } else { d }
  let a = g("a", 1.0)
  let two-d = ltype in ("oblique", "rectangular", "square", "hexagonal2d")
  (
    a: a,
    b: g("b", a),
    c: if two-d { 1.0 } else { g("c", a) },
    alpha: g("alpha", 90.0),
    beta: g("beta", 90.0),
    gamma: g("gamma", if ltype in ("trigonal", "hexagonal", "hexagonal2d") { 120.0 } else { 90.0 }),
  )
}

#let lattice-vectors(p) = {
  let (ca, cb, cg) = (calc.cos(p.alpha * 1deg), calc.cos(p.beta * 1deg), calc.cos(p.gamma * 1deg))
  let sg = calc.sin(p.gamma * 1deg)
  let cx = p.c * cb
  let cy = p.c * (ca - cb * cg) / sg
  let cz = calc.sqrt(calc.max(p.c * p.c - cx * cx - cy * cy, 0.0))
  (
    (p.a, 0.0, 0.0),
    (p.b * cg, p.b * sg, 0.0),
    (cx, cy, cz),
  )
}

#let frac-to-cart(vecs, frac, periodic) = {
  let r = vadd(vscale(vecs.at(0), frac.at(0)), vscale(vecs.at(1), frac.at(1)))
  if periodic.at(2) {
    vadd(r, vscale(vecs.at(2), frac.at(2)))
  } else {
    (r.at(0), r.at(1), r.at(2) + frac.at(2))  // z already in angstrom
  }
}
```

- [ ] **Step 4: Run test to verify it passes** — Expected: PASS.
- [ ] **Step 5: Commit**
```bash
git add -A && git commit -m "Add lattice module: per-system parameter validation and vectors"
```

---

### Task 6: Symmetry engine (`src/symmetry.typ`) + ground-truth fixtures

**Files:**
- Create: `src/symmetry.typ`, `tools/gen_fixtures.py`, `tests/fixtures/*.json` (generated)
- Test: `tests/test-symmetry.typ`

**Interfaces:**
- Consumes: `linalg.typ`, `data.typ` (`group-data`).
- Produces: `expand(group, sites, periodic) -> array of (element: str, frac: (f,f,f), site: int)` where `group` is a `group-data(..)` dict and each site is `(element: str, wyckoff: str, p: (x,y,z))` with unused vars zero. Panics if a Wyckoff letter is unknown or the orbit size ≠ multiplicity.

- [ ] **Step 1: Write the fixture generator**

`tools/gen_fixtures.py`:
```python
"""Ground-truth expansion fixtures.

3D cases: pymatgen Structure.from_spacegroup — an implementation INDEPENDENT of
pyxtal, so this genuinely cross-checks data/spacegroups.json.
Layer cases: expanded with pyxtal ops directly (weaker check — same source as the
data) plus hand-verified atom counts from the literature.
"""
import json
from pathlib import Path

import numpy as np
from pymatgen.core import Lattice, Structure

FIX = Path(__file__).resolve().parent.parent / "tests" / "fixtures"
FIX.mkdir(parents=True, exist_ok=True)

# name, sg, lattice-kwargs, sites: (element, wyckoff, rep_frac)
CASES_3D = [
    ("nacl", 225, dict(a=5.64), [("Na", "a", (0, 0, 0)), ("Cl", "b", (0.5, 0.5, 0.5))]),
    ("cscl", 221, dict(a=4.11), [("Cs", "a", (0, 0, 0)), ("Cl", "b", (0.5, 0.5, 0.5))]),
    ("diamond", 227, dict(a=3.567), [("C", "a", (0.125, 0.125, 0.125))]),
    ("zincblende", 216, dict(a=5.41), [("Zn", "a", (0, 0, 0)), ("S", "c", (0.25, 0.25, 0.25))]),
    ("wurtzite", 186, dict(a=3.25, c=5.21), [("Zn", "b", (1/3, 2/3, 0.0)), ("O", "b", (1/3, 2/3, 0.375))]),
    ("rutile", 136, dict(a=4.59, c=2.96), [("Ti", "a", (0, 0, 0)), ("O", "f", (0.305, 0.305, 0))]),
    ("perovskite", 221, dict(a=3.905), [("Sr", "a", (0, 0, 0)), ("Ti", "b", (0.5, 0.5, 0.5)), ("O", "c", (0, 0.5, 0.5))]),
    ("fluorite", 225, dict(a=5.46), [("Ca", "a", (0, 0, 0)), ("F", "c", (0.25, 0.25, 0.25))]),
    ("corundum", 167, dict(a=4.76, c=12.99, gamma=120), [("Al", "c", (0, 0, 0.352)), ("O", "e", (0.306, 0, 0.25))]),
    ("baddeleyite", 14, dict(a=5.15, b=5.21, c=5.32, beta=99.2),
     [("Zr", "e", (0.275, 0.040, 0.208)), ("O", "e", (0.070, 0.332, 0.345)), ("O", "e", (0.442, 0.755, 0.480))]),
]

for name, sg, lat, sites in CASES_3D:
    lattice = Lattice.from_parameters(
        lat.get("a"), lat.get("b", lat["a"]), lat.get("c", lat["a"]),
        lat.get("alpha", 90), lat.get("beta", 90), lat.get("gamma", 90))
    s = Structure.from_spacegroup(sg, lattice, [e for e, _, _ in sites], [c for _, _, c in sites])
    atoms = [{"element": site.specie.symbol, "frac": [round(x % 1.0, 6) for x in site.frac_coords]}
             for site in s]
    fixture = {
        "name": name, "kind": "3d", "group": sg,
        "ltype-params": lat,
        "sites": [{"element": e, "wyckoff": w,
                   "p": list(c)} for e, w, c in sites],
        "expected": {"natoms": len(atoms), "atoms": atoms},
    }
    (FIX / f"{name}.json").write_text(json.dumps(fixture, indent=1))
    print(f"{name}: sg {sg}, {len(atoms)} atoms")

# Layer-group cases (z of rep in angstrom); expected counts hand-verified:
# graphene: 2 C, hBN: 1 B + 1 N, MoS2 monolayer: 1 Mo + 2 S.
from pyxtal.symmetry import Group

CASES_LAYER = [
    ("graphene", 80, dict(a=2.46), [("C", None, (1/3, 2/3, 0.0))], 2),
    ("hbn", 78, dict(a=2.50), [("B", None, (1/3, 2/3, 0.0)), ("N", None, (2/3, 1/3, 0.0))], 2),
    ("mos2", 78, dict(a=3.16), [("Mo", None, (1/3, 2/3, 0.0)), ("S", None, (2/3, 1/3, 1.56))], 3),
]

def expand_layer(gnum, rep):
    ops = Group(gnum, dim=2).Wyckoff_positions[0].ops
    pts = []
    for op in ops:
        A = op.affine_matrix
        q = A[:3, :3] @ np.array(rep) + A[:3, 3]
        q[:2] %= 1.0
        if not any(np.allclose(np.minimum(np.abs(q[:2] - p[:2]), 1 - np.abs(q[:2] - p[:2])), 0, atol=1e-5)
                   and abs(q[2] - p[2]) < 1e-5 for p in pts):
            pts.append(q)
    return pts

for name, lg, lat, sites, total in CASES_LAYER:
    atoms, out_sites = [], []
    g = Group(lg, dim=2)
    for el, _, rep in sites:
        pts = expand_layer(lg, rep)
        # find the wyckoff letter whose representative matches: pick by multiplicity+position
        wp = next(w for w in g.Wyckoff_positions if w.multiplicity == len(pts))
        letter = "".join(ch for ch in wp.get_label() if ch.isalpha())
        out_sites.append({"element": el, "wyckoff": letter, "p": list(rep)})
        atoms += [{"element": el, "frac": [round(float(x), 6) for x in p]} for p in pts]
    assert len(atoms) == total, f"{name}: {len(atoms)} != {total}"
    fixture = {"name": name, "kind": "layer", "group": lg, "ltype-params": lat,
               "sites": out_sites, "expected": {"natoms": total, "atoms": atoms}}
    (FIX / f"{name}.json").write_text(json.dumps(fixture, indent=1))
    print(f"{name}: lg {lg}, {total} atoms, letters {[s['wyckoff'] for s in out_sites]}")
```

Run: `tools/.venv/bin/python tools/gen_fixtures.py`
Expected output includes `nacl: sg 225, 8 atoms`, `diamond: sg 227, 8 atoms`, `perovskite: sg 221, 5 atoms`, `graphene: lg 80, 2 atoms`, `mos2: lg 78, 3 atoms`.
**Known gotcha:** origin choice for SG 227 (diamond). pymatgen `from_spacegroup(227, ...)` uses origin choice 2 where 8a sits at (1/8,1/8,1/8). If the Typst test in Step 4 later fails ONLY for diamond, compare `group-data("3d", 227).wyckoff.a.t` against the fixture: if pyxtal uses origin choice 1 (8a at (0,0,0)), regenerate this one fixture with rep `(0,0,0)` and pymatgen's `Structure.from_spacegroup` replaced by explicitly applying pyxtal's setting, and record the setting choice in README. Do NOT fudge the engine.

- [ ] **Step 2: Write the failing Typst test**

`tests/test-symmetry.typ`:
```typst
#import "/src/symmetry.typ": expand
#import "/src/data.typ": group-data

#let frac-close(p, q, periodic) = {
  range(3).all(i => {
    let d = calc.abs(p.at(i) - q.at(i))
    let d = if periodic.at(i) { calc.min(d, 1.0 - d) } else { d }
    d < 1e-4
  })
}

#let fixtures = ("nacl", "cscl", "diamond", "zincblende", "wurtzite", "rutile",
                 "perovskite", "fluorite", "corundum", "baddeleyite",
                 "graphene", "hbn", "mos2")

#for name in fixtures {
  let fx = json("/tests/fixtures/" + name + ".json")
  let periodic = (true, true, fx.kind == "3d")
  let group = group-data(fx.kind, fx.group)
  let sites = fx.sites.map(s => (element: s.element, wyckoff: s.wyckoff, p: s.p))
  let atoms = expand(group, sites, periodic)
  assert(atoms.len() == fx.expected.natoms,
    message: fx.name + ": got " + str(atoms.len()) + " atoms, want " + str(fx.expected.natoms))
  for want in fx.expected.atoms {
    assert(
      atoms.any(a => a.element == want.element and frac-close(a.frac, want.frac, periodic)),
      message: fx.name + ": missing " + want.element + " at " + repr(want.frac),
    )
  }
}

// multiplicity spot-sweep with generic parameters (generator already sweeps ALL groups)
#for (kind, num) in (("3d", 2), ("3d", 14), ("3d", 62), ("3d", 136), ("3d", 167),
                     ("3d", 186), ("3d", 194), ("3d", 216), ("3d", 225), ("3d", 227), ("3d", 230),
                     ("layer", 1), ("layer", 8), ("layer", 49), ("layer", 65), ("layer", 78), ("layer", 80)) {
  let g = group-data(kind, num)
  let periodic = (true, true, kind == "3d")
  for (letter, w) in g.wyckoff {
    let atoms = expand(g, ((element: "C", wyckoff: letter, p: (0.1234, 0.2618, 0.3711)),), periodic)
    assert(atoms.len() == w.mult,
      message: kind + " " + str(num) + " wyckoff " + letter + ": " + str(atoms.len()) + " != " + str(w.mult))
  }
}
Symmetry OK
```

- [ ] **Step 3: Run test to verify it fails** — Expected: FAIL, `src/symmetry.typ` not found.

- [ ] **Step 4: Implement `src/symmetry.typ`**

```typst
#import "linalg.typ": mvec, vadd

#let _wrap(x) = calc.rem(calc.rem(x, 1.0) + 1.0, 1.0)

#let _close(p, q, periodic, eps) = {
  range(3).all(i => {
    let d = calc.abs(p.at(i) - q.at(i))
    let d = if periodic.at(i) { calc.min(d, 1.0 - d) } else { d }
    d < eps
  })
}

/// Expand Wyckoff sites into the full cell.
/// group: dict from data.group-data; sites: ((element, wyckoff, p), ..);
/// periodic: (bool, bool, bool). Returns ((element, frac, site), ..).
#let expand(group, sites, periodic, eps: 1e-4) = {
  let atoms = ()
  for (si, site) in sites.enumerate() {
    assert(
      site.wyckoff in group.wyckoff,
      message: "wyckoff: group " + group.symbol + " has no Wyckoff position '" + site.wyckoff
        + "' (available: " + group.wyckoff.keys().join(", ") + ")",
    )
    let w = group.wyckoff.at(site.wyckoff)
    let rep = vadd(mvec(w.m, site.p), w.t)
    let orbit = ()
    for op in group.ops {
      let q = vadd(mvec(op.at(0), rep), op.at(1))
      let q = range(3).map(i => if periodic.at(i) { _wrap(q.at(i)) } else { q.at(i) })
      if not orbit.any(o => _close(o, q, periodic, eps)) {
        orbit.push(q)
      }
    }
    assert(
      orbit.len() == w.mult,
      message: "wyckoff: site " + str(si) + " (" + site.element + " at " + site.wyckoff + " of "
        + group.symbol + ") expanded to " + str(orbit.len()) + " atoms, expected " + str(w.mult)
        + ". A free coordinate may coincide with a more special position.",
    )
    for q in orbit {
      atoms.push((element: site.element, frac: q, site: si))
    }
  }
  atoms
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `typst compile --root . tests/test-symmetry.typ tests/test-symmetry.pdf`
Expected: PASS (a few seconds — SG 225/227/230 sweeps are the heavy part). If only `diamond` fails, apply the origin-choice resolution documented in Step 1.

- [ ] **Step 6: Commit**
```bash
git add -A && git commit -m "Add symmetry engine with pymatgen ground-truth fixtures"
```

---

### Task 7: Public `structure()` constructor (`src/structure.typ`)

**Files:**
- Create: `src/structure.typ`
- Test: `tests/test-structure.typ`

**Interfaces:**
- Consumes: `lattice.typ`, `symmetry.typ`, `data.typ`.
- Produces the **structure value** used by everything downstream:
  ```
  (
    kind: "3d" | "layer",
    group: (number: int, symbol: str) | none,      // none for explicit input
    vectors: ((f,f,f), (f,f,f), (f,f,f)),          // cartesian lattice vectors, Å
    periodic: (bool, bool, bool),
    atoms: ((element: str, frac: (f,f,f), cart: (f,f,f), site: int), ..),
  )
  ```
- Signature: `structure(spacegroup: none, layergroup: none, lattice: (:), sites: (), atoms: ())`
  - exactly one of `spacegroup` / `layergroup` / (`lattice` as array-of-3-vectors + `atoms`) must be used;
  - `sites` entries: `(element: "Na", wyckoff: "a")` plus optional `x:`, `y:`, `z:` free coordinates;
  - explicit form: `lattice: ((..),(..),(..))`, `atoms: (("Sr", (0.5,0.5,0.5)), ..)`.
- Also produces `check-site(group, site) -> (ok, msg)` (pure validator for tests).

- [ ] **Step 1: Write the failing test**

`tests/test-structure.typ`:
```typst
#import "/src/structure.typ": structure, check-site
#import "/src/data.typ": group-data

// wyckoff-input path
#let nacl = structure(
  spacegroup: 225,
  lattice: (a: 5.64),
  sites: ((element: "Na", wyckoff: "a"), (element: "Cl", wyckoff: "b")),
)
#assert(nacl.kind == "3d" and nacl.atoms.len() == 8)
#assert(nacl.group.symbol == "Fm-3m")
#let cl = nacl.atoms.filter(a => a.element == "Cl").first()
#assert(cl.cart.len() == 3)

// free parameters via named args
#let rutile = structure(
  spacegroup: 136,
  lattice: (a: 4.59, c: 2.96),
  sites: ((element: "Ti", wyckoff: "a"), (element: "O", wyckoff: "f", x: 0.305)),
)
#assert(rutile.atoms.len() == 6)

// layer group
#let mos2 = structure(
  layergroup: 78,
  lattice: (a: 3.16),
  sites: (
    (element: "Mo", wyckoff: "a"),
    (element: "S", wyckoff: "h", z: 1.56),
  ),
)
#assert(mos2.kind == "layer" and mos2.periodic == (true, true, false))
#assert(mos2.atoms.len() == 3)
#assert(mos2.atoms.filter(a => a.element == "S").all(a => calc.abs(calc.abs(a.cart.at(2)) - 1.56) < 1e-6))

// explicit lattice + basis
#let sto = structure(
  lattice: ((3.9, 0, 0), (0, 3.9, 0), (0, 0, 3.9)),
  atoms: (("Sr", (0.5, 0.5, 0.5)), ("Ti", (0, 0, 0)),
          ("O", (0.5, 0, 0)), ("O", (0, 0.5, 0)), ("O", (0, 0, 0.5))),
)
#assert(sto.group == none and sto.atoms.len() == 5)

// validation surfaces good messages (pure checker)
#let g = group-data("3d", 136)
#assert(not check-site(g, (element: "O", wyckoff: "f")).ok, message: "136f needs x")
#assert(not check-site(g, (element: "O", wyckoff: "f", x: 0.3, y: 0.1)).ok, message: "y is not free on 136f")
#assert(not check-site(g, (element: "O", wyckoff: "q", x: 0.3)).ok, message: "no such letter")
#assert(check-site(g, (element: "O", wyckoff: "f", x: 0.305)).ok)
Structure OK
```

- [ ] **Step 2: Run test to verify it fails** — Expected: FAIL, file not found.

- [ ] **Step 3: Implement `src/structure.typ`**

```typst
#import "data.typ": group-data, element-info
#import "lattice.typ": lattice-params, lattice-vectors, frac-to-cart
#import "symmetry.typ": expand

#let check-site(group, site) = {
  if "element" not in site or "wyckoff" not in site {
    return (ok: false, msg: "each site needs (element: .., wyckoff: ..)")
  }
  if site.wyckoff not in group.wyckoff {
    return (ok: false, msg: "group " + group.symbol + " has no Wyckoff position '" + site.wyckoff
      + "' (available: " + group.wyckoff.keys().join(", ") + ")")
  }
  let w = group.wyckoff.at(site.wyckoff)
  let extra = site.keys().filter(k => k not in ("element", "wyckoff") and k not in w.vars)
  if extra.len() > 0 {
    return (ok: false, msg: "Wyckoff " + str(w.mult) + site.wyckoff + " of " + group.symbol
      + " does not have free coordinate(s) " + extra.join(", ")
      + if w.vars.len() > 0 { " (free: " + w.vars.join(", ") + ")" } else { " (no free coordinates)" })
  }
  let missing = w.vars.filter(v => v not in site)
  if missing.len() > 0 {
    return (ok: false, msg: "Wyckoff " + str(w.mult) + site.wyckoff + " of " + group.symbol
      + " requires free coordinate(s) " + missing.join(", "))
  }
  (ok: true, msg: "")
}

#let structure(spacegroup: none, layergroup: none, lattice: (:), sites: (), atoms: ()) = {
  let explicit = type(lattice) == array
  let n-modes = (int(spacegroup != none) + int(layergroup != none) + int(explicit))
  assert(n-modes == 1, message: "wyckoff: give exactly one of spacegroup:, layergroup:, or an explicit lattice: array with atoms:")

  if explicit {
    assert(lattice.len() == 3 and atoms.len() > 0,
      message: "wyckoff: explicit form needs lattice: (v1, v2, v3) and a non-empty atoms: list")
    let vecs = lattice.map(v => v.map(float))
    let periodic = (true, true, true)
    let alist = atoms.enumerate().map(((i, (el, frac))) => {
      let _ = element-info(el)  // validates the symbol
      (element: el, frac: frac.map(float), cart: frac-to-cart(vecs, frac.map(float), periodic), site: i)
    })
    return (kind: "3d", group: none, vectors: vecs, periodic: periodic, atoms: alist)
  }

  let (kind, number) = if spacegroup != none { ("3d", spacegroup) } else { ("layer", layergroup) }
  let group = group-data(kind, number)
  let periodic = (true, true, kind == "3d")
  assert(sites.len() > 0, message: "wyckoff: sites: must contain at least one site")
  for site in sites {
    let chk = check-site(group, site)
    assert(chk.ok, message: "wyckoff: " + chk.msg)
  }
  let esites = sites.map(s => (
    element: s.element,
    wyckoff: s.wyckoff,
    p: ("x", "y", "z").map(v => if v in s { float(s.at(v)) } else { 0.0 }),
  ))
  for s in sites { let _ = element-info(s.element) }
  let params = lattice-params(group.ltype, lattice)
  let vecs = lattice-vectors(params)
  let alist = expand(group, esites, periodic).map(a =>
    (..a, cart: frac-to-cart(vecs, a.frac, periodic)))
  (kind: kind, group: (number: number, symbol: group.symbol), vectors: vecs, periodic: periodic, atoms: alist)
}
```

- [ ] **Step 4: Run test to verify it passes.** If the MoS₂ case fails on the letter `h`, list the actual letters (`#group-data("layer", 78).wyckoff.keys()`) and fix the TEST to the letter whose `mult == 2` and `vars == ("z",)` — the fixture generator printed the right letters in Task 6.
- [ ] **Step 5: Commit**
```bash
git add -A && git commit -m "Add public structure() constructor with validation"
```

---

### Task 8: Geometry — boundary images + supercell (`src/geometry.typ`)

**Files:**
- Create: `src/geometry.typ`
- Test: `tests/test-geometry.typ`

**Interfaces:**
- Consumes: structure value (Task 7), `linalg.typ`, `lattice.typ`.
- Produces:
  - `display-atoms(structure, supercell: (1,1,1), boundary: true, eps: 1e-4) -> array of (element, frac, cart, site, image: bool)` — replicates over the supercell, then adds boundary copies (an atom with wrapped frac ≈ 0 or ≈ n along a periodic axis appears on both sides). `frac` here is in CELL units and may reach `n`.
  - `cell-edges(structure, supercell: (1,1,1)) -> array of (cart-a, cart-b)` — the 12 edges of every unit cell in the block, deduplicated; for layer structures the cell is drawn as its 2D parallelogram (4 edges at z = 0).

- [ ] **Step 1: Write the failing test**

`tests/test-geometry.typ`:
```typst
#import "/src/structure.typ": structure
#import "/src/geometry.typ": display-atoms, cell-edges

#let nacl = structure(
  spacegroup: 225,
  lattice: (a: 5.64),
  sites: ((element: "Na", wyckoff: "a"), (element: "Cl", wyckoff: "b")),
)

// textbook rocksalt cell: 14 Na (8 corners + 6 faces) + 13 Cl (12 edges + 1 center)
#let shown = display-atoms(nacl)
#assert(shown.len() == 27, message: "got " + str(shown.len()))
#assert(shown.filter(a => a.element == "Na").len() == 14)
#assert(shown.filter(a => a.element == "Cl").len() == 13)

// no boundary duplication when disabled
#assert(display-atoms(nacl, boundary: false).len() == 8)

// 2x1x1 supercell: corner plane atoms shared -> Na: 12 corners... just check totals grow consistently
#let sc = display-atoms(nacl, supercell: (2, 1, 1))
#assert(sc.filter(a => a.element == "Na").len() == 23, message: "12 integer-corner + 11 two-half-integer fcc points on the 2x1x1 block")
#assert(cell-edges(nacl).len() == 12)
#assert(cell-edges(nacl, supercell: (2, 1, 1)).len() == 20, message: "two cubes sharing a face: 24 - 4 shared")

// layer structure: cell drawn as 4 in-plane edges
#let mos2 = structure(
  layergroup: 78, lattice: (a: 3.16),
  sites: ((element: "Mo", wyckoff: "a"), (element: "S", wyckoff: "h", z: 1.56)),
)
#assert(cell-edges(mos2).len() == 4)
Geometry OK
```
(If the `21` for the 2×1×1 Na count is wrong at implementation time, count by hand before changing it: lattice points of an fcc 2×1×1 block at corners/faces/edges of the doubled box — corners 12? Work it out on paper and put the derivation in a comment next to the assert. Same discipline for any adjusted expected value in this file: derive, don't fit to the code.)

- [ ] **Step 2: Run test to verify it fails** — Expected: FAIL, file not found.

- [ ] **Step 3: Implement `src/geometry.typ` (this task's half)**

```typst
#import "linalg.typ": vadd, vscale, vsub, vlen
#import "lattice.typ": frac-to-cart

#let _cart(structure, frac) = frac-to-cart(structure.vectors, frac, structure.periodic)

/// Atoms to display: supercell replication + boundary images.
#let display-atoms(structure, supercell: (1, 1, 1), boundary: true, eps: 1e-4) = {
  let n = supercell
  let out = ()
  for a in structure.atoms {
    for i in range(n.at(0)) {
      for j in range(n.at(1)) {
        for k in range(if structure.periodic.at(2) { n.at(2) } else { 1 }) {
          let f = vadd(a.frac, (float(i), float(j), if structure.periodic.at(2) { float(k) } else { 0.0 }))
          out.push((element: a.element, frac: f, site: a.site, image: (i, j, k) != (0, 0, 0)))
        }
      }
    }
  }
  if boundary {
    let images = ()
    for a in out {
      // Per axis: the absolute coordinates this atom should appear at.
      // An atom at ~0 also appears at n; one at ~n also appears at 0.
      // (expand() wraps into [0,1), so within one cell only the ~0 case fires;
      // the ~n case matters for user-provided explicit atoms at exactly 1.0.)
      let targets = range(3).map(i => {
        let f = a.frac.at(i)
        if not structure.periodic.at(i) { (f,) }
        else if calc.abs(f) < eps { (f, float(n.at(i))) }
        else if calc.abs(f - float(n.at(i))) < eps { (f, 0.0) }
        else { (f,) }
      })
      for fx in targets.at(0) {
        for fy in targets.at(1) {
          for fz in targets.at(2) {
            if (fx, fy, fz) != (a.frac.at(0), a.frac.at(1), a.frac.at(2)) {
              images.push((..a, frac: (fx, fy, fz), image: true))
            }
          }
        }
      }
    }
    out += images
  }
  out.map(a => (..a, cart: _cart(structure, a.frac)))
}
```
Add one extra assertion in Step 1 alongside the NaCl counts: an explicit structure with an atom at exactly `(1.0, 0.5, 0.5)` must gain a boundary partner at `(0.0, 0.5, 0.5)`.

Continue `src/geometry.typ`:
```typst
/// Unit-cell wireframe edges for every cell in the supercell block, deduplicated.
#let cell-edges(structure, supercell: (1, 1, 1)) = {
  let n = supercell
  let corners-3d = ((0,0,0),(1,0,0),(0,1,0),(0,0,1),(1,1,0),(1,0,1),(0,1,1),(1,1,1))
  let edge-idx-3d = ((0,1),(0,2),(0,3),(1,4),(1,5),(2,4),(2,6),(3,5),(3,6),(4,7),(5,7),(6,7))
  let corners-2d = ((0,0,0),(1,0,0),(0,1,0),(1,1,0))
  let edge-idx-2d = ((0,1),(0,2),(1,3),(2,3))
  let (corners, edge-idx) = if structure.periodic.at(2) { (corners-3d, edge-idx-3d) } else { (corners-2d, edge-idx-2d) }
  let seen = ()
  let out = ()
  for i in range(n.at(0)) {
    for j in range(n.at(1)) {
      for k in range(if structure.periodic.at(2) { n.at(2) } else { 1 }) {
        for (p, q) in edge-idx {
          let fa = vadd(corners.at(p).map(float), (float(i), float(j), float(k)))
          let fb = vadd(corners.at(q).map(float), (float(i), float(j), float(k)))
          let key = repr((fa, fb))
          if key not in seen {
            seen.push(key)
            out.push((_cart(structure, fa), _cart(structure, fb)))
          }
        }
      }
    }
  }
  out
}
```

- [ ] **Step 4: Run test to verify it passes** — derive any mismatched count on paper per the test note before touching expected values.
- [ ] **Step 5: Commit**
```bash
git add -A && git commit -m "Add display-atoms (supercell + boundary images) and cell-edges"
```

---

### Task 9: Geometry — bonds

**Files:**
- Modify: `src/geometry.typ`
- Test: extend `tests/test-geometry.typ`

**Interfaces:**
- Produces: `find-bonds(shown, rules) -> array of (i: int, j: int)` — indices into the `display-atoms` output.
  - `rules == auto`: bond if `dist <= 1.15 × (r-cov(A) + r-cov(B))` and `dist >= 0.4` Å.
  - explicit rules: array of `(elements: ("Ti", "O"), max: 2.2)` with optional `min:` (default 0.4); element pair order-insensitive; ONLY listed pairs bond.

- [ ] **Step 1: Write the failing test (append to `tests/test-geometry.typ`)**

```typst
#import "/src/geometry.typ": find-bonds

// NaCl textbook cell: 54 Na-Cl bonds among the 27 displayed atoms
// (center Cl -> 6 face Na; each of 12 edge Cl -> 2 corner + 2 face Na)
#let bonds = find-bonds(shown, auto)
#assert(bonds.len() == 54, message: "got " + str(bonds.len()))
#for b in bonds {
  assert(shown.at(b.i).element != shown.at(b.j).element, message: "auto rule: no Na-Na/Cl-Cl at 2.82A")
}

// explicit rules: forbid everything except an impossible pair -> no bonds
#assert(find-bonds(shown, ((elements: ("Na", "Na"), max: 1.0),)).len() == 0)
// explicit Na-Cl cutoff
#assert(find-bonds(shown, ((elements: ("Na", "Cl"), max: 2.9),)).len() == 54)
Bonds OK
```

- [ ] **Step 2: Run to verify failure** — `find-bonds` not found.

- [ ] **Step 3: Implement (append to `src/geometry.typ`)**

```typst
#import "data.typ": element-info

/// O(N^2) bond search over displayed atoms. rules: auto | ((elements, max, min?), ..)
#let find-bonds(shown, rules) = {
  let cutoff(a, b) = {
    if rules == auto {
      let r = element-info(a.element).r-cov + element-info(b.element).r-cov
      (min: 0.4, max: 1.15 * r)
    } else {
      let hit = rules.find(r => (
        (r.elements.at(0), r.elements.at(1)) == (a.element, b.element)
          or (r.elements.at(1), r.elements.at(0)) == (a.element, b.element)
      ))
      if hit == none { none } else { (min: hit.at("min", default: 0.4), max: hit.max) }
    }
  }
  let out = ()
  for i in range(shown.len()) {
    for j in range(i + 1, shown.len()) {
      let c = cutoff(shown.at(i), shown.at(j))
      if c != none {
        let d = vlen(vsub(shown.at(i).cart, shown.at(j).cart))
        if d >= c.min and d <= c.max {
          out.push((i: i, j: j))
        }
      }
    }
  }
  out
}
```

- [ ] **Step 4: Run test to verify it passes.**
- [ ] **Step 5: Commit**
```bash
git add -A && git commit -m "Add bond detection (covalent-radii auto rule + explicit rules)"
```

---

### Task 10: Geometry — coordination polyhedra

**Files:**
- Modify: `src/geometry.typ`
- Test: extend `tests/test-geometry.typ`

**Interfaces:**
- Produces: `find-polyhedra(shown, bonds, elements) -> array of (center: int, faces: array of array of (f,f,f))` — one entry per displayed atom whose element is in `elements` and which has ≥ 4 bonded neighbors; each face is a planar polygon (vertices ordered around the face, outward normal) in cartesian Å.

- [ ] **Step 1: Write the failing test (append to `tests/test-geometry.typ`)**

```typst
#import "/src/geometry.typ": find-polyhedra

#let sto = structure(
  spacegroup: 221, lattice: (a: 3.905),
  sites: ((element: "Sr", wyckoff: "a"), (element: "Ti", wyckoff: "b"), (element: "O", wyckoff: "c")),
)
#let sshown = display-atoms(sto)
#let sbonds = find-bonds(sshown, ((elements: ("Ti", "O"), max: 2.2),))
#let polys = find-polyhedra(sshown, sbonds, ("Ti",))
// exactly one Ti displayed (cell center), octahedrally coordinated
#assert(polys.len() == 1, message: "got " + str(polys.len()))
#assert(polys.first().faces.len() == 8, message: "octahedron has 8 faces, got " + str(polys.first().faces.len()))
#assert(polys.first().faces.all(f => f.len() == 3))
Polyhedra OK
```
Note: the Ti at (½,½,½) needs all 6 O neighbors displayed — the 6 face-center O of the cell are exactly its octahedron. If the assertion finds 0 polyhedra, first check `sbonds` contains 6 Ti–O bonds.

- [ ] **Step 2: Run to verify failure** — `find-polyhedra` not found.

- [ ] **Step 3: Implement (append to `src/geometry.typ`)**

```typst
#import "linalg.typ": vcross, vdot, vnorm

/// Convex hull of <= ~12 points via unique-plane enumeration.
/// Returns faces as polygons (vertices ordered around the outward normal).
#let _hull-faces(pts) = {
  let n = pts.len()
  let faces = ()
  let seen = ()
  for i in range(n) {
    for j in range(i + 1, n) {
      for k in range(j + 1, n) {
        let nrm = vcross(vsub(pts.at(j), pts.at(i)), vsub(pts.at(k), pts.at(i)))
        if vlen(nrm) < 1e-8 { continue }
        let nrm = vnorm(nrm)
        let d = vdot(nrm, pts.at(i))
        let sides = pts.map(p => vdot(nrm, p) - d)
        if sides.any(s => s > 1e-6) and sides.any(s => s < -1e-6) { continue }
        let (nrm, d) = if sides.any(s => s > 1e-6) { (vscale(nrm, -1), -d) } else { (nrm, d) }
        let key = repr(nrm.map(x => calc.round(x, digits: 5)) + (calc.round(d, digits: 5),))
        if key in seen { continue }
        seen.push(key)
        let fpts = pts.filter(p => calc.abs(vdot(nrm, p) - d) < 1e-6)
        // order around centroid
        let c = vscale(fpts.fold((0.0, 0.0, 0.0), vadd), 1 / fpts.len())
        let u = vnorm(vsub(fpts.first(), c))
        let v = vcross(nrm, u)
        faces.push(fpts.sorted(key: p => {
          let r = vsub(p, c)
          calc.atan2(vdot(r, u), vdot(r, v)).rad()
        }))
      }
    }
  }
  faces
}

/// Coordination polyhedra around displayed atoms of the given elements.
#let find-polyhedra(shown, bonds, elements) = {
  let out = ()
  for (ci, c) in shown.enumerate() {
    if c.element not in elements { continue }
    let nbrs = ()
    for b in bonds {
      if b.i == ci { nbrs.push(shown.at(b.j).cart) }
      if b.j == ci { nbrs.push(shown.at(b.i).cart) }
    }
    if nbrs.len() >= 4 {
      out.push((center: ci, faces: _hull-faces(nbrs)))
    }
  }
  out
}
```
Check `calc.atan2` argument order in the Typst docs (it is `calc.atan2(x, y)`) — the sort key only needs a consistent angular order, but verify the call compiles and returns an angle; `.rad()` converts to a sortable float.

- [ ] **Step 4: Run test to verify it passes.**
- [ ] **Step 5: Commit**
```bash
git add -A && git commit -m "Add coordination polyhedra via unique-plane convex hull"
```

---

### Task 11: Projection + scene builder (`src/project.typ`, `src/scene.typ`)

**Files:**
- Create: `src/project.typ`, `src/scene.typ`
- Test: `tests/test-scene.typ`

**Interfaces:**
- Consumes: geometry outputs (Tasks 8–10), `data.typ`, `linalg.typ`.
- Produces:
  - `project.typ`: `projector(view) -> function (x,y,z) -> (sx: f, sy: f, depth: f)`. `view: (azimuth: angle, elevation: angle)`. Definition (pin with tests): `x1 = x·cos(az) + y·sin(az)`, `y1 = −x·sin(az) + y·cos(az)`, then `sx = x1`, `sy = −y1·sin(el) + z·cos(el)`, `depth = y1·cos(el) + z·sin(el)` (larger depth = closer to viewer).
  - `scene.typ`: `build-scene(structure, view: .., supercell: .., bonds: .., polyhedra: .., radius: ..) -> (prims: (..), bbox: (min-x, min-y, max-x, max-y), elements: (..))`
    Primitive kinds (all carry `depth`):
    - `(kind: "sphere", c: (sx, sy), r: f, color: color, element: str, depth: f)` — `r = radius × r-atom`, in Å.
    - `(kind: "seg", a: (sx,sy), b: (sx,sy), color: color, w: f, depth: f)` — bond half, `w = 0.16` Å; endpoints pulled to sphere surfaces (start offset `0.9 × r_display` along the bond).
    - `(kind: "face", pts: ((sx,sy), ..), color: color, depth: f)` — polyhedron face; depth = centroid depth − 0.01 (bias: vertex atoms draw over their faces).
    - `(kind: "edge", a: (sx,sy), b: (sx,sy), depth: f)` — cell edges pre-split into 8 sub-segments each, each with its own midpoint depth.
    - `elements`: deduplicated element list in first-appearance order (for the legend).

- [ ] **Step 1: Write the failing test**

`tests/test-scene.typ`:
```typst
#import "/src/project.typ": projector
#import "/src/structure.typ": structure
#import "/src/scene.typ": build-scene

// pin the projection convention
#let p0 = projector((azimuth: 0deg, elevation: 0deg))
#let s = p0((1.0, 0.0, 0.0))
#assert(calc.abs(s.sx - 1.0) < 1e-9 and calc.abs(s.sy) < 1e-9)
#let s = p0((0.0, 0.0, 1.0))
#assert(calc.abs(s.sy - 1.0) < 1e-9 and calc.abs(s.depth) < 1e-9)
#let s = p0((0.0, 1.0, 0.0))
#assert(calc.abs(s.depth - 1.0) < 1e-9, message: "+y toward viewer at az=el=0")
#let top = projector((azimuth: 0deg, elevation: 90deg))((0.0, 0.0, 1.0))
#assert(calc.abs(top.depth - 1.0) < 1e-9, message: "top view: +z toward viewer")

#let nacl = structure(
  spacegroup: 225, lattice: (a: 5.64),
  sites: ((element: "Na", wyckoff: "a"), (element: "Cl", wyckoff: "b")),
)
#let sc = build-scene(nacl, view: (azimuth: 30deg, elevation: 15deg))
#let spheres = sc.prims.filter(p => p.kind == "sphere")
#assert(spheres.len() == 27)
#assert(sc.prims.filter(p => p.kind == "seg").len() == 108, message: "54 bonds x 2 halves")
#assert(sc.prims.filter(p => p.kind == "edge").len() == 96, message: "12 edges x 8 splits")
#assert(sc.elements == ("Na", "Cl"))
#assert(sc.bbox.at(0) < sc.bbox.at(2))
// polyhedra path
#let sto = structure(
  spacegroup: 221, lattice: (a: 3.905),
  sites: ((element: "Sr", wyckoff: "a"), (element: "Ti", wyckoff: "b"), (element: "O", wyckoff: "c")),
)
#let sc2 = build-scene(sto, view: (azimuth: 30deg, elevation: 15deg),
  bonds: ((elements: ("Ti", "O"), max: 2.2),), polyhedra: ("Ti",))
#assert(sc2.prims.filter(p => p.kind == "face").len() == 8)
Scene OK
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement `src/project.typ`**

```typst
/// Orthographic projector. Convention (pinned by tests/test-scene.typ):
/// az=el=0 looks along +y with +x right, +z up; depth grows toward the viewer.
#let projector(view) = {
  let az = view.at("azimuth", default: 25deg)
  let el = view.at("elevation", default: 15deg)
  p => {
    let (x, y, z) = p
    let x1 = x * calc.cos(az) + y * calc.sin(az)
    let y1 = -x * calc.sin(az) + y * calc.cos(az)
    (
      sx: x1,
      sy: -y1 * calc.sin(el) + z * calc.cos(el),
      depth: y1 * calc.cos(el) + z * calc.sin(el),
    )
  }
}
```

- [ ] **Step 4: Implement `src/scene.typ`**

```typst
#import "linalg.typ": vadd, vsub, vscale, vnorm, vlen, lerp
#import "data.typ": element-info
#import "geometry.typ": display-atoms, cell-edges, find-bonds, find-polyhedra
#import "project.typ": projector

#let build-scene(
  structure,
  view: (azimuth: 25deg, elevation: 15deg),
  supercell: (1, 1, 1),
  bonds: auto,          // auto | none | rules array
  polyhedra: (),        // element list
  radius: 0.45,
  bond-width: 0.16,
) = {
  let proj = projector(view)
  let shown = display-atoms(structure, supercell: supercell)
  let prims = ()

  let rdisp(el) = radius * element-info(el).r-atom
  for a in shown {
    let s = proj(a.cart)
    prims.push((kind: "sphere", c: (s.sx, s.sy), r: rdisp(a.element),
      color: element-info(a.element).color, element: a.element, depth: s.depth))
  }

  let blist = if bonds == none { () } else { find-bonds(shown, bonds) }
  for b in blist {
    let (pa, pb) = (shown.at(b.i), shown.at(b.j))
    let dir = vnorm(vsub(pb.cart, pa.cart))
    let a0 = vadd(pa.cart, vscale(dir, 0.9 * rdisp(pa.element)))
    let b0 = vsub(pb.cart, vscale(dir, 0.9 * rdisp(pb.element)))
    let mid = lerp(a0, b0, 0.5)
    for (p, q, el) in ((a0, mid, pa.element), (mid, b0, pb.element)) {
      let (sp, sq, sm) = (proj(p), proj(q), proj(lerp(p, q, 0.5)))
      prims.push((kind: "seg", a: (sp.sx, sp.sy), b: (sq.sx, sq.sy),
        color: element-info(el).color.darken(10%), w: bond-width, depth: sm.depth))
    }
  }

  if polyhedra.len() > 0 {
    for poly in find-polyhedra(shown, blist, polyhedra) {
      let col = element-info(shown.at(poly.center).element).color
      for f in poly.faces {
        let spts = f.map(p => proj(p))
        let cdepth = spts.map(s => s.depth).sum() / spts.len()
        prims.push((kind: "face", pts: spts.map(s => (s.sx, s.sy)), color: col, depth: cdepth - 0.01))
      }
    }
  }

  for (ea, eb) in cell-edges(structure, supercell: supercell) {
    for t in range(8) {
      let p = lerp(ea, eb, t / 8)
      let q = lerp(ea, eb, (t + 1) / 8)
      let sm = proj(lerp(p, q, 0.5))
      let (sp, sq) = (proj(p), proj(q))
      prims.push((kind: "edge", a: (sp.sx, sp.sy), b: (sq.sx, sq.sy), depth: sm.depth))
    }
  }

  let xs = ()
  let ys = ()
  for p in prims {
    if p.kind == "sphere" {
      xs += (p.c.at(0) - p.r, p.c.at(0) + p.r)
      ys += (p.c.at(1) - p.r, p.c.at(1) + p.r)
    } else if p.kind == "face" {
      xs += p.pts.map(q => q.at(0)); ys += p.pts.map(q => q.at(1))
    } else {
      xs += (p.a.at(0), p.b.at(0)); ys += (p.a.at(1), p.b.at(1))
    }
  }
  let elements = ()
  for a in shown {
    if a.element not in elements { elements.push(a.element) }
  }
  (
    prims: prims,
    bbox: (calc.min(..xs), calc.min(..ys), calc.max(..xs), calc.max(..ys)),
    elements: elements,
  )
}
```

- [ ] **Step 5: Run test to verify it passes.**
- [ ] **Step 6: Commit**
```bash
git add -A && git commit -m "Add orthographic projector and depth-keyed scene builder"
```

---

### Task 12: Renderer core (`src/render.typ`) — spheres + edges + scaling

**Files:**
- Create: `src/render.typ`
- Test: `tests/test-render.typ` (compile + human eyeball of a PNG)

**Interfaces:**
- Consumes: scene (Task 11), cetz 0.5.2.
- Produces:
  - `draw-scene(scene, scale: 1.0) -> cetz draw commands` (usable inside any `cetz.canvas`) — depth-sorts `scene.prims` and draws them; coordinates multiplied by `scale` (canvas units per Å).
  - `render(scene, width: 8cm, legend: true, axes-info: none) -> content` — wraps `draw-scene` in `cetz.canvas(length: 1cm, ..)` with `scale = (width in cm) / bbox width`.

**Before coding: read `~/tcode/cetz/src/draw/shapes.typ` (circle, line signatures and style args), `~/tcode/cetz/src/styles.typ`, and two gallery files, per Global Constraints.**

- [ ] **Step 1: Write the compile test**

`tests/test-render.typ`:
```typst
#import "/src/structure.typ": structure
#import "/src/scene.typ": build-scene
#import "/src/render.typ": render

#let nacl = structure(
  spacegroup: 225, lattice: (a: 5.64),
  sites: ((element: "Na", wyckoff: "a"), (element: "Cl", wyckoff: "b")),
)
#render(build-scene(nacl), width: 8cm)
```

- [ ] **Step 2: Run to verify failure** — `src/render.typ` not found.

- [ ] **Step 3: Implement `src/render.typ`**

```typst
#import "@preview/cetz:0.5.2"

#let _sphere-fill(col) = gradient.radial(
  (white.mix((col, 55%)), 0%),
  (col, 60%),
  (col.darken(20%), 100%),
  center: (35%, 30%),
  radius: 120%,
)

#let draw-scene(scene, scale: 1.0) = {
  import cetz.draw: *
  let s = scale
  let pt(p) = (p.at(0) * s, p.at(1) * s)
  for p in scene.prims.sorted(key: p => p.depth) {
    if p.kind == "face" {
      line(..p.pts.map(pt), close: true,
        fill: p.color.transparentize(55%),
        stroke: (paint: p.color.darken(35%), thickness: 0.5pt))
    } else if p.kind == "edge" {
      line(pt(p.a), pt(p.b), stroke: (paint: luma(90), thickness: 0.6pt))
    } else if p.kind == "seg" {
      line(pt(p.a), pt(p.b),
        stroke: (paint: p.color, thickness: p.w * s * 1cm, cap: "round"))
    } else if p.kind == "sphere" {
      circle(pt(p.c), radius: p.r * s,
        fill: _sphere-fill(p.color),
        stroke: (paint: p.color.darken(45%), thickness: 0.5pt))
    }
  }
}

#let render(scene, width: 8cm, legend: true, axes-info: none) = {
  let (x0, y0, x1, y1) = scene.bbox
  let s = (width / 1cm) / (x1 - x0)
  cetz.canvas(length: 1cm, {
    import cetz.draw: *
    draw-scene(scene, scale: s)
    // legend and axes are added in Task 13; keep parameters stable now
  })
}
```
Check against the cetz sources you read: `gradient.radial` stop syntax (`(color, offset)` pairs), `white.mix((col, 55%))` mixing signature, and whether `circle` fill accepts a gradient (it does — gallery uses gradients). If `white.mix` syntax fights you, use `color.mix((white, 45%), (col, 55%))`.

- [ ] **Step 4: Compile and eyeball**

Run:
```bash
typst compile --root . tests/test-render.typ tests/test-render.png --format png --ppi 180
open tests/test-render.png
```
Expected: a recognizable rocksalt unit cell — shaded purple-ish Na and green Cl spheres (Jmol colors), gray cell edges correctly occluded by front atoms, two-tone bonds. **Judge it against a Materials Project NaCl render** (attach the PNG for the user in the task report). Iterate on gradient stops/stroke weights here until it looks right — this step is the design gate for the whole package.

- [ ] **Step 5: Commit**
```bash
git add -A && git commit -m "Add cetz renderer core: shaded spheres, bonds, cell edges"
```

---

### Task 13: Renderer completion — polyhedra, labels, legend, axes triad

**Files:**
- Modify: `src/render.typ`, `src/scene.typ`
- Test: extend `tests/test-render.typ`

**Interfaces:**
- `build-scene` gains `labels: false` (adds `(kind: "label", at: (sx,sy), text: str, depth: ∞-ish)` prims — element symbol, or site label; drawn last).
- `render` gains working `legend: true` (element swatch + name rows to the right of the bbox) and `axes: true` via `axes-info: (vectors, view)` — a small triad of the projected a/b/c directions (a/b only for layer structures) drawn below-left of the bbox with arrows and italic labels.

- [ ] **Step 1: Extend the test**

Append to `tests/test-render.typ`:
```typst
#pagebreak()
// perovskite with TiO6 octahedra, legend, axes
#let sto = structure(
  spacegroup: 221, lattice: (a: 3.905),
  sites: ((element: "Sr", wyckoff: "a"), (element: "Ti", wyckoff: "b"), (element: "O", wyckoff: "c")),
)
#render(
  build-scene(sto, bonds: ((elements: ("Ti", "O"), max: 2.2),), polyhedra: ("Ti",), labels: true),
  width: 8cm, legend: true, axes-info: (vectors: sto.vectors, view: (azimuth: 25deg, elevation: 15deg)),
)

#pagebreak()
// MoS2 slab: layer group, no c edges
#let mos2 = structure(
  layergroup: 78, lattice: (a: 3.16),
  sites: ((element: "Mo", wyckoff: "a"), (element: "S", wyckoff: "h", z: 1.56)),
)
#render(build-scene(mos2, supercell: (4, 4, 1)), width: 10cm)
```

- [ ] **Step 2: Compile — should already compile but WITHOUT legend/axes/labels visible. Verify the new pages render, then implement the additions.**

- [ ] **Step 3: Implement**

In `src/scene.typ`, add parameter `labels: false` to `build-scene`; after the sphere loop:
```typst
  if labels {
    for a in shown {
      let s = proj(a.cart)
      prims.push((kind: "label", at: (s.sx, s.sy), text: a.element, depth: 1e9))
    }
  }
```
(`depth: 1e9` guarantees labels sort last.)

In `src/render.typ` `draw-scene`, add the branch:
```typst
    } else if p.kind == "label" {
      content(pt(p.at), text(size: 7pt, fill: black, weight: "bold", p.text))
```
And complete `render`:
```typst
#import "data.typ": element-info
#import "project.typ": projector
#import "linalg.typ": vnorm

#let render(scene, width: 8cm, legend: true, axes-info: none) = {
  let (x0, y0, x1, y1) = scene.bbox
  let s = (width / 1cm) / (x1 - x0)
  cetz.canvas(length: 1cm, {
    import cetz.draw: *
    draw-scene(scene, scale: s)
    if legend {
      for (i, el) in scene.elements.enumerate() {
        let y = y1 * s - i * 0.55
        circle((x1 * s + 0.7, y), radius: 0.16,
          fill: _sphere-fill(element-info(el).color),
          stroke: (paint: element-info(el).color.darken(45%), thickness: 0.4pt))
        content((x1 * s + 1.0, y), anchor: "west", text(size: 9pt, el))
      }
    }
    if axes-info != none {
      let proj = projector(axes-info.view)
      let names = ("a", "b", "c")
      let origin = (x0 * s - 0.5, y0 * s - 0.5)
      let naxes = axes-info.at("n-axes", default: 3)
      for i in range(naxes) {
        let d = proj(vnorm(axes-info.vectors.at(i)))
        let tip = (origin.at(0) + d.sx * 0.7, origin.at(1) + d.sy * 0.7)
        line(origin, tip, mark: (end: ">", fill: black), stroke: 0.7pt)
        content((origin.at(0) + d.sx * 0.95, origin.at(1) + d.sy * 0.95),
          text(size: 8pt, style: "italic", names.at(i)))
      }
    }
  })
}
```
For layer structures pass `n-axes: 2` (wired in Task 14's `crystal()`).

- [ ] **Step 4: Compile and eyeball all three pages**

Run: `typst compile --root . tests/test-render.typ tests/test-render-{n}.png --format png --ppi 180`
Expected: page 2 shows the classic SrTiO₃ figure — green Sr spheres, a translucent TiO₆ octahedron at the center with red O at face centers, legend on the right, a/b/c triad bottom-left. Page 3 shows a 4×4 MoS₂ slab viewed obliquely with only the in-plane cell outline. Iterate visually. Attach PNGs in the task report.

- [ ] **Step 5: Commit**
```bash
git add -A && git commit -m "Complete renderer: polyhedra, labels, legend, axes triad"
```

---

### Task 14: Public API assembly — `crystal()`, `crystal-group()`, `lib.typ`

**Files:**
- Modify: `lib.typ`
- Create: `src/crystal.typ`
- Test: extend `tests/test-render.typ` + new `tests/test-api.typ`

**Interfaces:**
- Produces the spec's user-facing calls:
  - `crystal(structure, view: (azimuth: 25deg, elevation: 15deg), supercell: (1,1,1), bonds: auto, polyhedra: (), labels: false, legend: true, axes: true, radius: 0.45, width: 8cm) -> content`
  - `crystal-group(structure, ..same visual options.., scale: 1.0) -> cetz draw commands` (no width/legend/axes — composition mode; scale = canvas units per Å)
  - `lib.typ` exports: `structure`, `crystal`, `crystal-group`, `prototypes` (Task 15 fills prototypes; export the module now with a placeholder-free empty module is NOT allowed — export prototypes only in Task 15).

- [ ] **Step 1: Write the failing test**

`tests/test-api.typ`:
```typst
#import "/lib.typ": structure, crystal, crystal-group
#import "@preview/cetz:0.5.2"

#let nacl = structure(
  spacegroup: 225, lattice: (a: 5.64),
  sites: ((element: "Na", wyckoff: "a"), (element: "Cl", wyckoff: "b")),
)
#crystal(nacl, width: 6cm)

// composition: crystal inside a user canvas with an annotation
#cetz.canvas(length: 1cm, {
  import cetz.draw: *
  crystal-group(nacl, scale: 0.5)
  content((3, -1.5), [conventional cell of NaCl])
})
```

- [ ] **Step 2: Run to verify failure** — `structure` not exported from `lib.typ`.

- [ ] **Step 3: Implement `src/crystal.typ` and `lib.typ`**

`src/crystal.typ`:
```typst
#import "scene.typ": build-scene
#import "render.typ": render, draw-scene

#let _default-view = (azimuth: 25deg, elevation: 15deg)

#let crystal(
  structure,
  view: _default-view,
  supercell: (1, 1, 1),
  bonds: auto,
  polyhedra: (),
  labels: false,
  legend: true,
  axes: true,
  radius: 0.45,
  width: 8cm,
) = {
  let scene = build-scene(structure, view: view, supercell: supercell,
    bonds: bonds, polyhedra: polyhedra, labels: labels, radius: radius)
  render(scene, width: width, legend: legend,
    axes-info: if axes {
      (vectors: structure.vectors, view: view,
       n-axes: if structure.periodic.at(2) { 3 } else { 2 })
    } else { none })
}

#let crystal-group(
  structure,
  view: _default-view,
  supercell: (1, 1, 1),
  bonds: auto,
  polyhedra: (),
  labels: false,
  radius: 0.45,
  scale: 1.0,
) = {
  let scene = build-scene(structure, view: view, supercell: supercell,
    bonds: bonds, polyhedra: polyhedra, labels: labels, radius: radius)
  draw-scene(scene, scale: scale)
}
```

`lib.typ`:
```typst
#import "src/structure.typ": structure
#import "src/crystal.typ": crystal, crystal-group
```

- [ ] **Step 4: Run all tests**

Run: `make test`
Expected: every `tests/test-*.typ` passes.

- [ ] **Step 5: Commit**
```bash
git add -A && git commit -m "Assemble public API: crystal() and crystal-group()"
```

---

### Task 15: Prototype library (`src/prototypes.typ`)

**Files:**
- Create: `src/prototypes.typ`
- Modify: `lib.typ`
- Test: `tests/test-prototypes.typ`

**Interfaces:**
- Produces module `prototypes` with:
  `sc(el, a:)`, `fcc(el, a:)`, `bcc(el, a:)`, `hcp(el, a:, c:)`, `diamond(el, a:)`,
  `rocksalt(A, B, a:)`, `cesium-chloride(A, B, a:)`, `zincblende(A, B, a:)`,
  `wurtzite(A, B, a:, c:, u: 0.375)`, `fluorite(A, B, a:)`, `rutile(A, B, a:, c:, x: 0.305)`,
  `perovskite(A, B, X, a:)`, `graphene(el: "C", a: 2.46)`, `hexagonal-bn(a: 2.50)`,
  `tmd(M, X, a:, z:)` — each returns a structure value.

- [ ] **Step 1: Write the failing test**

`tests/test-prototypes.typ`:
```typst
#import "/lib.typ": prototypes
#let p = prototypes

#assert(p.fcc("Cu", a: 3.61).atoms.len() == 4)
#assert(p.bcc("Fe", a: 2.87).atoms.len() == 2)
#assert(p.sc("Po", a: 3.35).atoms.len() == 1)
#assert(p.hcp("Mg", a: 3.21, c: 5.21).atoms.len() == 2)
#assert(p.diamond("Si", a: 5.43).atoms.len() == 8)
#assert(p.rocksalt("Na", "Cl", a: 5.64).atoms.len() == 8)
#assert(p.cesium-chloride("Cs", "Cl", a: 4.11).atoms.len() == 2)
#assert(p.zincblende("Ga", "As", a: 5.65).atoms.len() == 8)
#assert(p.wurtzite("Ga", "N", a: 3.19, c: 5.19).atoms.len() == 4)
#assert(p.fluorite("Ca", "F", a: 5.46).atoms.len() == 12)
#assert(p.rutile("Ti", "O", a: 4.59, c: 2.96).atoms.len() == 6)
#assert(p.perovskite("Sr", "Ti", "O", a: 3.905).atoms.len() == 5)
#assert(p.graphene().atoms.len() == 2)
#assert(p.hexagonal-bn().atoms.len() == 2)
#assert(p.tmd("Mo", "S", a: 3.16, z: 1.56).atoms.len() == 3)
Prototypes OK
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement `src/prototypes.typ`**

```typst
// Named structure prototypes. Wyckoff letters follow data/*.json (pyxtal, standard settings).
#import "structure.typ": structure

#let sc(el, a: none) = structure(spacegroup: 221, lattice: (a: a),
  sites: ((element: el, wyckoff: "a"),))
#let fcc(el, a: none) = structure(spacegroup: 225, lattice: (a: a),
  sites: ((element: el, wyckoff: "a"),))
#let bcc(el, a: none) = structure(spacegroup: 229, lattice: (a: a),
  sites: ((element: el, wyckoff: "a"),))
#let hcp(el, a: none, c: none) = structure(spacegroup: 194, lattice: (a: a, c: c),
  sites: ((element: el, wyckoff: "c"),))
#let diamond(el, a: none) = structure(spacegroup: 227, lattice: (a: a),
  sites: ((element: el, wyckoff: "a"),))
#let rocksalt(A, B, a: none) = structure(spacegroup: 225, lattice: (a: a),
  sites: ((element: A, wyckoff: "a"), (element: B, wyckoff: "b")))
#let cesium-chloride(A, B, a: none) = structure(spacegroup: 221, lattice: (a: a),
  sites: ((element: A, wyckoff: "a"), (element: B, wyckoff: "b")))
#let zincblende(A, B, a: none) = structure(spacegroup: 216, lattice: (a: a),
  sites: ((element: A, wyckoff: "a"), (element: B, wyckoff: "c")))
#let wurtzite(A, B, a: none, c: none, u: 0.375) = structure(spacegroup: 186, lattice: (a: a, c: c),
  sites: ((element: A, wyckoff: "b", z: 0.0), (element: B, wyckoff: "b", z: u)))
#let fluorite(A, B, a: none) = structure(spacegroup: 225, lattice: (a: a),
  sites: ((element: A, wyckoff: "a"), (element: B, wyckoff: "c")))
#let rutile(A, B, a: none, c: none, x: 0.305) = structure(spacegroup: 136, lattice: (a: a, c: c),
  sites: ((element: A, wyckoff: "a"), (element: B, wyckoff: "f", x: x)))
#let perovskite(A, B, X, a: none) = structure(spacegroup: 221, lattice: (a: a),
  sites: ((element: A, wyckoff: "a"), (element: B, wyckoff: "b"), (element: X, wyckoff: "c")))
#let graphene(el: "C", a: 2.46) = structure(layergroup: 80, lattice: (a: a),
  sites: ((element: el, wyckoff: "c"),))
#let hexagonal-bn(a: 2.50) = structure(layergroup: 78, lattice: (a: a),
  sites: ((element: "B", wyckoff: "a"), (element: "N", wyckoff: "d")))
#let tmd(M, X, a: none, z: none) = structure(layergroup: 78, lattice: (a: a),
  sites: ((element: M, wyckoff: "a"), (element: X, wyckoff: "h", z: z)))
```
The Wyckoff LETTERS here are provisional where marked by test failures: for each failing prototype, list the group's letters and multiplicities from the data (`group-data(kind, n).wyckoff`) and pick the letter whose multiplicity and representative match the crystallographic description in the comment (e.g. hcp = the 2-fold site at (1/3,2/3,1/4) in SG 194; graphene = the 2-fold site at (1/3,2/3,0) in LG 80; hBN = the two 1-fold sites at (1/3,2/3,0) and (2/3,1/3,0) in LG 78). Fix the prototype, never the engine. Diamond follows whatever origin choice Task 6 recorded.

Add to `lib.typ`:
```typst
#import "src/prototypes.typ"
```

- [ ] **Step 4: Run test to verify it passes, then `make test` for the full suite.**
- [ ] **Step 5: Commit**
```bash
git add -A && git commit -m "Add prototype structure library"
```

---

### Task 16: Examples, README gallery, images

**Files:**
- Create: `examples/nacl.typ`, `examples/perovskite.typ`, `examples/diamond.typ`, `examples/mos2.typ`, `examples/gallery.typ`, `README.md`, `images/` (generated PNGs, committed)
- Modify: `Makefile` (images target already exists), `typst.toml` (verify `exclude` covers `images/*`)

**Interfaces:**
- Consumes the whole public API exactly as an end user would (`#import "/lib.typ"` with root; the published form is `@preview/wyckoff:0.1.0` — note this in README).

- [ ] **Step 1: Write the four single-figure examples**

`examples/nacl.typ`:
```typst
#import "/lib.typ": prototypes, crystal
#set page(width: auto, height: auto, margin: 0.4cm)
#crystal(prototypes.rocksalt("Na", "Cl", a: 5.64), width: 8cm)
```

`examples/perovskite.typ`:
```typst
#import "/lib.typ": prototypes, crystal
#set page(width: auto, height: auto, margin: 0.4cm)
#crystal(
  prototypes.perovskite("Sr", "Ti", "O", a: 3.905),
  bonds: ((elements: ("Ti", "O"), max: 2.2),),
  polyhedra: ("Ti",),
  width: 8cm,
)
```

`examples/diamond.typ`:
```typst
#import "/lib.typ": prototypes, crystal
#set page(width: auto, height: auto, margin: 0.4cm)
#crystal(prototypes.diamond("C", a: 3.567), width: 8cm)
```

`examples/mos2.typ`:
```typst
#import "/lib.typ": prototypes, crystal
#set page(width: auto, height: auto, margin: 0.4cm)
#crystal(prototypes.tmd("Mo", "S", a: 3.16, z: 1.56), supercell: (4, 4, 1), width: 10cm)
```

`examples/gallery.typ`: a 2×2 grid of the four figures with captions (plain `#grid`).

- [ ] **Step 2: Generate images and eyeball every one**

Run: `mkdir -p images && make images && open images/`
Expected: four publication-quality PNGs. This is the second visual gate — compare with Materials Project / VESTA renders of the same structures; iterate on any visual defect (sphere shading, bond radius, polyhedron opacity, edge weight) before proceeding. Show them to the user.

- [ ] **Step 3: Write `README.md`**

Structure (write real prose, not this outline): title + one-line pitch; the gallery grid embedding `images/*.png`; Quick start (`#import "@preview/wyckoff:0.1.0"` + the NaCl three-liner); Specifying structures (three input modes with one example each — space group + Wyckoff incl. a CrystalFormer note, layer groups with the z-in-Å rule, explicit lattice+basis); `crystal()` option reference table; prototype list; "How it works" (pre-generated pyxtal tables, painter's algorithm, known limitations: intersecting translucent polyhedra, large supercells slow, standard settings only); Roadmap (CIF import, Brillouin zones, WASM engine); Development (venv, `make data|fixtures|test`); the space-group origin/setting note recorded in Task 6; license.

- [ ] **Step 4: Full test suite + commit**
```bash
make test
git add -A && git commit -m "Add examples, gallery images, and README"
```

---

### Task 17: CI + Universe submission prep

**Files:**
- Create: `.github/workflows/ci.yml`
- Modify: `typst.toml` (final review)

- [ ] **Step 1: Write CI**

`.github/workflows/ci.yml`:
```yaml
name: CI
on:
  push: {branches: [main]}
  pull_request:
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: typst-community/setup-typst@v4
        with: {typst-version: '0.14.2'}
      - run: make test
```

- [ ] **Step 2: Push the repo and verify CI is green**

```bash
gh repo create GiggleLiu/wyckoff --public --source . --push
gh run watch
```
Expected: CI passes. (If the user prefers a different owner/org, ask before creating.)

- [ ] **Step 3: Universe submission checklist (do not submit without user sign-off)**

- `typst.toml` `exclude` keeps the package lean (docs, tools, tests, examples, images, CI excluded); `data/*.json` MUST ship.
- README renders correctly on GitHub; images referenced with absolute GitHub URLs in the copy submitted to Universe if relative paths don't resolve there (check how `ptable-amat` handled it in `~/tcode/packages`).
- In the user's `~/tcode/packages` fork (GiggleLiu/packages): sync with upstream `typst/packages`, copy the package to `packages/preview/wyckoff/0.1.0/` per the repo's CONTRIBUTING.md, compile a smoke test against the vendored copy, open the PR.
- Ask the user to review the PR before it goes out.

- [ ] **Step 4: Final commit**
```bash
git add -A && git commit -m "Add CI workflow"
```

---

## Verification (whole-project, after all tasks)

1. `make test` — all suites green.
2. `make images` — four gallery figures look Materials-Project-comparable (human judgment, with the user).
3. Fresh-eyes API walkthrough: follow README quick-start verbatim in a scratch file; it must work exactly as written.
4. Engine trust chain: fixtures came from pymatgen (independent of pyxtal); the generator's multiplicity sweep covered all 310 groups; the Typst sweep re-checks 17 groups end-to-end through the real data files.
