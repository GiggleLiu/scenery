# M4 Stage 3 (Visualization) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The creative/aesthetic stage of M4. Four deliverables: (#27) a van-der-Waals radius column in the element data (the mechanical foundation for CPK); (#28) render modes on `crystal()`/`crystal-group()`/`molecule()` — `ball-and-stick` (default, pixel-identical to today), `space-filling`/`cpk` (vdW spheres, no bonds), `licorice` (uniform thin sticks with matching caps) — plus a single-color opt-out of the two-tone bond split; (#29) a perspective camera mode in the scenery core, whose real work is the audit of every consumer that mixes a WORLD radius with SCREEN units (all orthographic assumptions today); (#30) a specular-highlight shading polish that intentionally repaints every committed baseline image, followed by the milestone's main gate cost: a reviewed, image-by-image rebaseline.

**Architecture:** Pure Typst; the Rust plugin is untouched this stage. Three layers change: `scenery/src/camera.typ` gains a perspective branch in `project()` plus one new exported helper `project-scale(cam, depth)` (the screen-per-world magnification at a given camera depth; exactly `1.0` for orthographic/2d — this identity is what keeps every existing call site byte-identical). `scenery/src/render.typ` multiplies world radii/widths by that factor at exactly four sites (`_projected-sphere`, `_record`'s sphere radius, seg thickness, arrow thickness/head) and gains an opt-outable specular stop in `_sphere-gradient`. `wyckoff/src/figure.typ` gains the `mode:`/`bond-color:` scene options and applies `project-scale` at its two world-radius-in-screen-space sites (the screen bbox and the `occlude()` coverage heuristic). The depth-interval logic in `render.typ` (`_depth-half`, `_line-sphere-occlusion`) needs no code change: it consumes `sp.r` from `_projected-sphere`, which now arrives pre-scaled.

**Tech Stack:** Typst 0.14.2 + cetz 0.5.2; pymatgen (tools venv, `Element.van_der_waals_radius` — verified present in the installed pymatgen 2026.5.4, returning a `FloatWithUnit` in Å or `None`); GNU Make; existing CI (no workflow change).

Implements issues #27 (r-vdw data), #28 (render modes), #29 (perspective camera), #30 (shading polish + rebaseline). Design: `docs/plans/2026-07-12-file-import-molecular-rendering-design.md` (see "Visualization changes", "Data changes", "Testing & gates").

## Global Constraints

- **Orthographic and 2d projection stay byte-identical.** `scenery/tests/test-camera.typ:17` pins the 2d path with exact dict equality (`flat == (sx: 3, sy: 4, depth: 0)`); the orthographic `camera()` dict must keep exactly its current three keys `(mode, azimuth, elevation)` (perspective fields appear only on perspective cameras). `project-scale` returns the literal `1.0` for non-perspective cameras, so every `x * project-scale(...)` call site is value-identical on the orthographic path.
- **Ball-and-stick stays pixel-identical** until Task 6 deliberately repaints. Two gates enforce this: (a) data-level — default `build-scene(...)` prims must be exactly equal to `mode: "ball-and-stick"` prims, and the untouched `wyckoff/tests/test-scene.typ` keeps passing; (b) pixel-level — Tasks 2 and 5 end by regenerating every example PNG and asserting `git status` shows **zero** modified images.
- **Committed baselines:** `wyckoff/images/*.png` (9 files today), `scenery/images/*.png` (5 tracked: flow, hero, primitives, solids, visibility), `brillouin/images/*.png` (3 files) are the pixel-identical gallery gate. They are regenerated + committed ONLY when a task intentionally repaints (new examples in Tasks 3/5; everything in Task 6). Regeneration command per package: `TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C <pkg> images` (all three Makefiles render examples at 144 ppi).
- Typst tests run from the **repo root**: `make pkgroot && TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff test` (same pattern for `scenery`/`brillouin`). wyckoff imports scenery via `@preview/scenery:0.1.0`, resolved through the `_pkgroot` symlink tree — scenery edits are visible to wyckoff immediately after `make pkgroot`.
- **Working-tree hygiene:** the repo has pre-existing untracked/dirty files that are NOT part of this stage (`AGENTS.md`, `.DS_Store`, `scenery/.DS_Store`, `scenery/examples/c60.typ`, `scenery/images/c60.png`, a dirty `scenery/README.md`). Never `git add` them; every commit below lists its files explicitly. Note: `make -C scenery images` will (re)write the untracked `scenery/images/c60.png` because the images target loops over all examples — leave it untracked.
- No Rust/plugin change this stage; `wyckoff/plugin/wyckoff_io.wasm` must not be rebuilt or committed.
- Data regeneration goes through the tools venv: `make -C wyckoff data` runs `../tools/.venv/bin/python ../tools/gen_elements.py` (and `gen_groups.py`). If the venv is missing, `make -C wyckoff venv` first.
- Radii are Ångström floats. The elements.json schema after Task 1 (one new key, everything else unchanged):
  ```json
  { "<symbol>": { "color": "#RRGGBB", "color-vesta": "#RRGGBB",
                  "r-atom": f, "r-cov": f, "r-vdw": f } }
  ```
- **Perspective convention (the contract Tasks 4–5 target):** view-space is the existing pinned orthographic frame (`sx0, sy0, depth` per `camera.typ:44-52`); a perspective camera sits at `depth = +distance` (world units, toward the viewer) looking at the origin plane; the projected point is `(sx0·s, sy0·s)` with `s = distance / (distance − depth)`, and the **depth key is the unscaled view depth** (same monotone far-to-near ordering as today). A world radius `r` at depth `d` projects to screen radius `r · s(d)`. `distance → ∞` degenerates to orthographic.

---

### Task 1: `r-vdw` data column (issue #27)

**Files:**
- Modify: `tools/gen_elements.py`
- Regenerate + commit: `wyckoff/data/elements.json`
- Modify: `wyckoff/src/data.typ` (expose `r-vdw` from `element-info`, currently lines 10–15)
- Modify: `wyckoff/tests/test-data.typ`

**Interfaces:**
- Produces (Python): each elements.json entry gains `"r-vdw": <float Å>` — `float(Element.van_der_waals_radius)` (pymatgen's Bondi-style table; O = 1.52, C = 1.70, H = 1.10, Na = 2.27), fallback `1.5 * r-atom` where pymatgen has no value. **NOT raw r-atom**: an atomic radius is roughly half a vdW radius and would render fallback atoms visibly shrunken in CPK mode (design-doc rule). In the installed pymatgen only Z ≥ 103 lack vdW data and those elements aren't in elements.json (96 entries), so the fallback is defensive, not load-bearing.
- Produces (Typst): `element-info(symbol)` returns `(color, color-vesta, r-cov, r-atom, r-vdw)`.
- Consumes: nothing new. Downstream consumer is Task 2's space-filling mode.

- [ ] **Step 1: Write the failing Typst test**

Append to `wyckoff/tests/test-data.typ` (after the `element-info("Ti")` line, before the `group-data` import):

```typ
// van der Waals radii (issue #27): pymatgen table, Å.
#assert(calc.abs(o.r-vdw - 1.52) < 0.01, message: "O vdW radius ~1.52")
#assert(calc.abs(element-info("C").r-vdw - 1.70) < 0.01, message: "C vdW radius ~1.70")
#assert(calc.abs(element-info("H").r-vdw - 1.10) < 0.05, message: "H vdW radius ~1.10")
#assert(na.r-vdw > 2.2 and na.r-vdw < 2.35, message: "Na vdW radius ~2.27")
#assert(o.r-vdw > o.r-atom and na.r-vdw > na.r-atom,
  message: "vdW radius must exceed the atomic radius")
#assert(type(o.r-vdw) == float, message: "r-vdw must be a float")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `make pkgroot && TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff test`
Expected: FAIL in `tests/test-data.typ` — dictionary `element-info(..)` has no key `r-vdw` (the generator hasn't run and `data.typ` doesn't expose it).

- [ ] **Step 3: Extend the generator**

In `tools/gen_elements.py`, replace the `data[sym] = {...}` block and its asserts (currently the `data[sym] = {` dict through the two `isinstance` asserts) with:

```python
    r_atom_eff = float(r_atom if r_atom is not None else r_cov)
    # van der Waals radius for CPK/space-filling mode. pymatgen's table covers
    # every element we emit; where it is ever missing, fall back to 1.5*r-atom
    # (raw r-atom is roughly HALF a vdW radius and would render fallback atoms
    # visibly shrunken in CPK mode -- see the M4 design doc, "Data changes").
    r_vdw = el.van_der_waals_radius  # FloatWithUnit (angstrom) or None
    r_vdw_eff = float(r_vdw) if r_vdw is not None else 1.5 * r_atom_eff
    data[sym] = {
        "color": hexcolor(EL_COLORS["Jmol"].get(sym, (128, 128, 128))),
        "color-vesta": hexcolor(EL_COLORS["VESTA"].get(sym, (128, 128, 128))),
        "r-cov": round(float(r_cov if r_cov is not None else r_atom), 3),
        "r-atom": round(r_atom_eff, 3),
        "r-vdw": round(r_vdw_eff, 3),
    }
    # Schema contract: radii are always floats (json() preserves int vs float).
    for key in ("r-cov", "r-atom", "r-vdw"):
        assert isinstance(data[sym][key], float), f"{sym} {key} not float"
    assert 0.9 < data[sym]["r-vdw"] < 4.0, f"{sym} r-vdw {data[sym]['r-vdw']} out of range"
```

and after the existing `assert abs(data["O"]["r-cov"] - 0.66) < 0.05` add:

```python
assert abs(data["O"]["r-vdw"] - 1.52) < 0.01, "O vdW must be 1.52 (pymatgen/Bondi)"
assert abs(data["C"]["r-vdw"] - 1.70) < 0.01, "C vdW must be 1.70"
assert data["Na"]["r-vdw"] > data["Na"]["r-atom"], "vdW must exceed atomic radius"
```

Also update the module docstring (line 1) to `"""Generate data/elements.json: Jmol/VESTA colors + covalent/atomic/van-der-Waals radii per element."""`.

- [ ] **Step 4: Regenerate the data**

Run: `make -C wyckoff data`
Expected: `wrote .../wyckoff/data/elements.json (96 elements)` (pymatgen may print `No data available for van_der_waals_radius` warnings for super-heavy elements it iterates over — harmless; they are filtered out before emission). Then:

Run: `git status --short wyckoff/data tools/`
Expected: exactly two modifications — `wyckoff/data/elements.json` and `tools/gen_elements.py`. **Negative control:** `spacegroups.json`/`layergroups.json` must NOT appear (proves `gen_groups.py` is deterministic and the data pipeline didn't drift). Spot-check: `python3 -c "import json; d=json.load(open('wyckoff/data/elements.json')); print(d['O'], d['C'])"` shows `'r-vdw': 1.52` and `'r-vdw': 1.7` alongside the unchanged color/r-atom/r-cov values.

- [ ] **Step 5: Expose `r-vdw` in `data.typ`**

In `wyckoff/src/data.typ`, extend the `element-info` return dict (lines 10–15) to:

```typ
  (
    color: rgb(e.color),
    color-vesta: rgb(e.color-vesta),
    r-cov: e.r-cov,
    r-atom: e.r-atom,
    r-vdw: e.r-vdw,
  )
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff test`
Expected: `tests/test-data.typ` passes; suite ends `All tests passed!`.

- [ ] **Step 7: Commit**

```bash
git add tools/gen_elements.py wyckoff/data/elements.json wyckoff/src/data.typ wyckoff/tests/test-data.typ
git commit -m "feat(wyckoff): van der Waals radius column r-vdw in element data (#27)"
```

---

### Task 2: render modes + single-color bonds in `build-scene` and the figure API (issue #28)

**Files:**
- Modify: `wyckoff/src/figure.typ` (`build-scene`, lines 23–132)
- Modify: `wyckoff/src/crystal.typ` (all three entry points)
- Create: `wyckoff/tests/test-modes.typ`

**Interfaces:**
- Produces (Typst, `figure.typ`):
  ```typ
  #let build-scene(
    structure,
    view: (azimuth: 25deg, elevation: 15deg),
    supercell: (1, 1, 1),
    mode: "ball-and-stick",   // | "space-filling" | "cpk" (alias) | "licorice"
    bonds: auto,
    bond-color: auto,         // auto = two-tone split (current); a color = ONE seg per bond
    polyhedra: (),
    radius: auto,
    bond-width: auto,
    labels: false,
    colors: (:),
  )
  ```
- Produces (Typst, `crystal.typ`): `crystal(...)` and `crystal-group(...)` gain `mode: "ball-and-stick"` and `bond-color: auto`, and their `radius: 0.45` default becomes `radius: auto`; `molecule(...)`'s existing (accepted-but-unused) `mode:` is now threaded through, it gains `bond-color: auto`, and `radius: 0.45` becomes `auto`. All forwarded verbatim to `build-scene`.
- **Mode semantics (the contract the tests pin):**

  | mode | sphere radius | bonds | polyhedra |
  |---|---|---|---|
  | `ball-and-stick` | `radius × r-atom` (auto radius = 0.45) — **bit-for-bit today's behavior** | two-tone halves, trimmed by `0.9 × rdisp` at each end, width 0.16 | allowed |
  | `space-filling` / `cpk` | `radius × r-vdw` (auto radius = 1.0 — full vdW) | **none** (bond search skipped entirely) | **assert-rejected** if non-empty |
  | `licorice` | uniform `radius × bond-width` (auto radius = 0.55; element-independent caps just wider than the stick's half-width 0.5) | two-tone halves, **untrimmed** (atom-center to midpoint; the cap sphere covers the joint), width auto = 0.25 | allowed (unusual, but harmless) |

  `radius: auto` resolves per mode (0.45 / 1.0 / 0.55); a numeric `radius` keeps today's meaning in ball-and-stick (× r-atom), scales r-vdw in space-filling, and scales bond-width in licorice. `bond-width: auto` resolves to 0.25 in licorice, 0.16 otherwise.
- **`bond-color` semantics:** `auto` keeps the existing two-tone split (each half `color-of(el).darken(10%)`, split at the bond midpoint — bit-for-bit today's loop). A `color` value draws ONE `seg` per bond spanning the full (trimmed) bond in that verbatim color — fewer primitives and one clean depth key per bond. Applies to ball-and-stick and licorice; irrelevant to space-filling.
- Consumes: `element-info(el).r-vdw` (Task 1).

- [ ] **Step 1: Pre-flight — verify the committed baselines are current**

Before touching any code, prove the pixel gate has a clean starting point:

```bash
make pkgroot
TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff images
git status --short wyckoff/images
```

Expected: **no output** from `git status` (every regenerated PNG is byte-identical to its committed baseline — Typst renders deterministically). If any image differs here, STOP and report: the baselines are stale from a previous change, and the zero-diff controls in Steps 6 and Task 5 would be meaningless. Do not proceed until adjudicated.

- [ ] **Step 2: Write the failing mode tests**

Create `wyckoff/tests/test-modes.typ`:

```typ
#import "/src/structure.typ": structure
#import "/src/figure.typ": build-scene
#import "/src/data.typ": element-info

// Water: 3 atoms, 2 O-H bonds (find-bonds covalent rule; pinned by
// test-molecule.typ as 4 two-tone segs).
#let water = structure(atoms: (
  ("O", (0.0, 0.0, 0.0)),
  ("H", (0.757, 0.586, 0.0)),
  ("H", (-0.757, 0.586, 0.0)),
))

// THE BALL-AND-STICK GATE AT DATA LEVEL: the default output must be exactly
// equal to an explicit mode: "ball-and-stick". (test-scene.typ, untouched,
// additionally pins that this default equals the pre-mode-era output.)
#let default-scene = build-scene(water)
#let bas = build-scene(water, mode: "ball-and-stick")
#assert.eq(default-scene.prims, bas.prims)
#assert.eq(default-scene.bbox, bas.bbox)
// auto radius in ball-and-stick means today's 0.45 x r-atom
#let o-sphere = default-scene.prims.filter(p => p.kind == "sphere").first()
#assert(calc.abs(o-sphere.r - 0.45 * element-info("O").r-atom) < 1e-12)

// space-filling: full vdW spheres, NO bond segs.
#let cpk = build-scene(water, mode: "space-filling")
#let cpk-spheres = cpk.prims.filter(p => p.kind == "sphere")
#assert.eq(cpk-spheres.len(), 3)
#assert.eq(cpk.prims.filter(p => p.kind == "seg").len(), 0,
  message: "space-filling draws no bonds")
#assert(calc.abs(cpk-spheres.at(0).r - element-info("O").r-vdw) < 1e-9)
#assert(calc.abs(cpk-spheres.at(1).r - element-info("H").r-vdw) < 1e-9)
// "cpk" is a pure alias
#assert.eq(build-scene(water, mode: "cpk").prims, cpk.prims)
// a numeric radius scales the vdW spheres
#let cpk-half = build-scene(water, mode: "space-filling", radius: 0.5)
#assert(calc.abs(cpk-half.prims.first().r - 0.5 * element-info("O").r-vdw) < 1e-9)

// licorice: uniform caps at 0.55 x bond-width; untrimmed two-tone sticks.
#let lic = build-scene(water, mode: "licorice")
#let lic-spheres = lic.prims.filter(p => p.kind == "sphere")
#assert(lic-spheres.all(p => calc.abs(p.r - 0.55 * 0.25) < 1e-12),
  message: "licorice caps are element-independent: 0.55 x bond-width")
#let lic-segs = lic.prims.filter(p => p.kind == "seg")
#assert.eq(lic-segs.len(), 4, message: "2 bonds x 2 two-tone halves")
#assert(lic-segs.all(p => calc.abs(p.w - 0.25) < 1e-12))
#assert.eq(lic-segs.first().a, (0.0, 0.0, 0.0),
  message: "licorice bonds are untrimmed: they start at the atom center")

// bond-color opt-out: ONE seg per bond, verbatim color, both relevant modes.
#let single = build-scene(water, bond-color: luma(100))
#let single-segs = single.prims.filter(p => p.kind == "seg")
#assert.eq(single-segs.len(), 2, message: "single-color bonds are not split")
#assert(single-segs.all(p => p.color == luma(100)))
// the single seg spans the same trimmed extent as the two-tone pair
#assert.eq(single-segs.first().a, default-scene.prims.filter(p => p.kind == "seg").first().a)
#assert.eq(single-segs.first().b, default-scene.prims.filter(p => p.kind == "seg").at(1).b)
#let lic-single = build-scene(water, mode: "licorice", bond-color: luma(100))
#assert.eq(lic-single.prims.filter(p => p.kind == "seg").len(), 2)

Modes OK
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff test`
Expected: FAIL — `build-scene` has no `mode` argument (`unexpected argument: mode`).

- [ ] **Step 4: Implement the modes in `build-scene`**

In `wyckoff/src/figure.typ`, replace the `build-scene` signature and body from its current line 23 (`#let build-scene(`) through line 75 (the end of the bond loop) with the following. The bbox / polyhedra / cell-edge / return blocks below the bond loop are UNCHANGED except where noted. Everything on the `ball-and-stick` + `bond-color: auto` path evaluates the exact same expressions as today, in the same order — that is the pixel gate.

```typ
#let build-scene(
  structure,
  view: (azimuth: 25deg, elevation: 15deg),
  supercell: (1, 1, 1),
  mode: "ball-and-stick",  // | "space-filling"/"cpk" | "licorice"
  bonds: auto,          // auto | none | rules array
  bond-color: auto,     // auto = two-tone split halves | a color = one seg per bond
  polyhedra: (),        // element list
  radius: auto,         // per-mode default: 0.45 (b&s), 1.0 (cpk), 0.55 (licorice)
  bond-width: auto,     // per-mode default: 0.25 (licorice), 0.16 otherwise
  labels: false,
  colors: (:),
) = {
  assert(mode in ("ball-and-stick", "space-filling", "cpk", "licorice"),
    message: "wyckoff: mode must be \"ball-and-stick\", \"space-filling\" (alias \"cpk\") or \"licorice\", got " + repr(mode))
  let mode = if mode == "cpk" { "space-filling" } else { mode }
  assert(mode != "space-filling" or polyhedra.len() == 0,
    message: "wyckoff: space-filling mode draws no polyhedra; drop the polyhedra: option")
  assert(bond-color == auto or type(bond-color) == color,
    message: "wyckoff: bond-color must be auto or a color, got " + repr(bond-color))
  let bond-width = if bond-width == auto {
    if mode == "licorice" { 0.25 } else { 0.16 }
  } else { bond-width }
  let radius = if radius == auto {
    if mode == "space-filling" { 1.0 } else if mode == "licorice" { 0.55 } else { 0.45 }
  } else { radius }

  let az = view.at("azimuth", default: 25deg)
  let elev = view.at("elevation", default: 15deg)
  let cam = scenery.camera(azimuth: az, elevation: elev)

  // Depth-only offset: the old renderer pushed polyhedra faces back by 0.01 in
  // depth (`cdepth - 0.01`). The camera-forward direction changes ONLY depth
  // (screen x/y are invariant), so offsetting face vertices along it by -0.01
  // reproduces the old depth key exactly while leaving projected geometry — and
  // hence the screen bbox and every drawn pixel — untouched.
  let gdepth = (-calc.sin(az) * calc.cos(elev), calc.cos(az) * calc.cos(elev), calc.sin(elev))
  let face-offset = scenery.vscale(gdepth, -0.01)

  let shown = display-atoms(structure, supercell: supercell)
  let prims = ()
  // Displayed sphere radius per mode. Ball-and-stick is today's exact formula;
  // space-filling uses the full van der Waals radius (CPK); licorice caps are
  // element-independent, slightly wider (0.55) than the stick's half-width
  // (0.50 x bond-width) so the round cap joint is seamlessly covered.
  let rdisp(el) = if mode == "space-filling" { radius * element-info(el).r-vdw }
    else if mode == "licorice" { radius * bond-width }
    else { radius * element-info(el).r-atom }
  let color-of(el) = colors.at(el, default: element-info(el).color)

  // Spheres, then labels, then bond segs, then polyhedra faces, then cell edges:
  // this push order is the stable-sort tie-break the old renderer relied on.
  for a in shown {
    prims.push(scenery.sphere(a.cart, rdisp(a.element),
      color: color-of(a.element), element: a.element))
  }
  if labels {
    for a in shown {
      prims.push(scenery.label(a.cart, a.element))
    }
  }

  // Space-filling shows the raw packing: skip the bond search entirely.
  let blist = if mode == "space-filling" or bonds == none { () } else { find-bonds(shown, bonds) }
  for b in blist {
    let (pa, pb) = (shown.at(b.i), shown.at(b.j))
    let dir = scenery.vnorm(scenery.vsub(pb.cart, pa.cart))
    // Ball-and-stick trims each bond end to 90% of the sphere radius (today's
    // rule); licorice sticks run atom-center to atom-center — their caps have
    // the same radius as the stick, so the joint is hidden by the cap sphere.
    let trim(el) = if mode == "licorice" { 0.0 } else { 0.9 * rdisp(el) }
    let a0 = scenery.vadd(pa.cart, scenery.vscale(dir, trim(pa.element)))
    let b0 = scenery.vsub(pb.cart, scenery.vscale(dir, trim(pb.element)))
    if bond-color == auto {
      let mid = scenery.lerp(a0, b0, 0.5)
      // Two-tone bond: one seg per half, coloured by its own atom.
      for (p, q, el) in ((a0, mid, pa.element), (mid, b0, pb.element)) {
        prims.push(scenery.seg(p, q,
          color: color-of(el).darken(10%), w: bond-width))
      }
    } else {
      // Single-color opt-out: one seg per bond, verbatim color.
      prims.push(scenery.seg(a0, b0, color: bond-color, w: bond-width))
    }
  }
```

(The subsequent `if polyhedra.len() > 0 { ... }`, cell-edge, bbox, elements and return blocks stay exactly as they are, lines 77–132 today.)

- [ ] **Step 5: Thread `mode`/`bond-color` through `crystal.typ`**

Replace `wyckoff/src/crystal.typ` in full:

```typ
#import "figure.typ": build-scene, render, draw-scene

#let _default-view = (azimuth: 25deg, elevation: 15deg)

#let crystal(
  structure,
  view: _default-view,
  supercell: (1, 1, 1),
  mode: "ball-and-stick",
  bonds: auto,
  bond-color: auto,
  polyhedra: (),
  labels: false,
  legend: true,
  axes: true,
  radius: auto,
  colors: (:),
  width: 8cm,
) = {
  let scene = build-scene(structure, view: view, supercell: supercell,
    mode: mode, bonds: bonds, bond-color: bond-color, polyhedra: polyhedra,
    labels: labels, radius: radius, colors: colors)
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
  mode: "ball-and-stick",
  bonds: auto,
  bond-color: auto,
  polyhedra: (),
  labels: false,
  radius: auto,
  colors: (:),
  scale: 1.0,
) = {
  let scene = build-scene(structure, view: view, supercell: supercell,
    mode: mode, bonds: bonds, bond-color: bond-color, polyhedra: polyhedra,
    labels: labels, radius: radius, colors: colors)
  draw-scene(scene, scale: scale)
}

/// Render a non-periodic molecule: atoms + bonds, no unit cell, no
/// crystallographic triad. Same scene options as crystal().
/// mode: "ball-and-stick" (default) | "space-filling"/"cpk" | "licorice".
#let molecule(
  structure,
  view: _default-view,
  bonds: auto,
  bond-color: auto,
  labels: false,
  legend: true,
  radius: auto,
  colors: (:),
  mode: "ball-and-stick",
  width: 8cm,
) = {
  let scene = build-scene(structure, view: view, supercell: (1, 1, 1),
    mode: mode, bonds: bonds, bond-color: bond-color, polyhedra: (),
    labels: labels, radius: radius, colors: colors)
  render(scene, width: width, legend: legend, axes-info: none)
}
```

- [ ] **Step 6: Run the suite and the zero-diff pixel control**

Run: `TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff test`
Expected: all tests pass — including the NEW `test-modes.typ` AND the UNTOUCHED `test-scene.typ` (27 spheres / 108 segs / 96 edges — the data-level negative control that ball-and-stick didn't move) and `test-molecule.typ` (4 two-tone segs).

Run:

```bash
TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff images
git status --short wyckoff/images
```

Expected: **no output** — every existing example (all of which use the default mode) renders byte-identically. Any modified PNG here means the ball-and-stick path changed and MUST be fixed before committing.

- [ ] **Step 7: Verify the negative control (invalid mode errors clearly)**

```bash
printf '#import "/lib.typ": structure, molecule\n#let w = structure(atoms: (("O", (0.0, 0.0, 0.0)),))\n#molecule(w, mode: "sticks")\n' > wyckoff/tests/neg-mode.typ
(TYPST_PACKAGE_PATH="$PWD/_pkgroot" typst compile --root wyckoff wyckoff/tests/neg-mode.typ /tmp/neg-mode.pdf; echo "exit=$?")
rm wyckoff/tests/neg-mode.typ
```

Expected: compile FAILS, `exit=` nonzero, error message contains `mode must be "ball-and-stick"` — never a silent fallback. (Temp file named `neg-*.typ` so the `tests/test-*.typ` glob never picks it up.)

- [ ] **Step 8: Commit**

```bash
git add wyckoff/src/figure.typ wyckoff/src/crystal.typ wyckoff/tests/test-modes.typ
git commit -m "feat(wyckoff): render modes - space-filling/cpk + licorice + single-color bonds (#28)"
```

---

### Task 3: render-modes showcase example (issue #28, creative payoff)

**Files:**
- Create: `wyckoff/examples/render-modes.typ`
- Create + commit: `wyckoff/images/render-modes.png`
- Modify: `wyckoff/README.md`

**Interfaces:** consumes Task 2's `mode:`/`bond-color:` API only. The molecule is benzene built with exact trigonometry in Typst (no fixture file, no invented coordinates): C ring at 1.39 Å, H radially at 2.48 Å. The auto bond rule finds exactly the 6 C–C (1.39 < 1.15×(0.73+0.73)=1.68) and 6 C–H (1.09 < 1.15×(0.73+0.31)=1.20) bonds and no others (second-neighbour C–C is 2.41).

- [ ] **Step 1: Write the example**

Create `wyckoff/examples/render-modes.typ`:

```typ
#import "/lib.typ": structure, molecule, crystal, prototypes

#set page(width: auto, height: auto, margin: 0.6cm)
#set text(font: "New Computer Modern", size: 10pt)

// Benzene, constructed exactly: carbon hexagon of circumradius 1.39 Å (equal
// to the C-C bond length), hydrogens radially outward at 2.48 Å (C-H 1.09 Å).
#let ring(el, r) = range(6).map(k =>
  (el, (r * calc.cos(k * 60deg), r * calc.sin(k * 60deg), 0.0)))
#let benzene = structure(atoms: ring("C", 1.39) + ring("H", 2.48))
#let v = (azimuth: 20deg, elevation: 60deg)

#let cell(fig, caption) = align(center)[
  #fig
  #v(0.2cm)
  #caption
]

#grid(
  columns: 3,
  column-gutter: 0.9cm,
  row-gutter: 0.8cm,
  cell(
    molecule(benzene, view: v, legend: false, width: 4.6cm),
    [`ball-and-stick` (default)],
  ),
  cell(
    molecule(benzene, view: v, mode: "licorice", legend: false, width: 4.6cm),
    [`licorice`],
  ),
  cell(
    molecule(benzene, view: v, mode: "space-filling", legend: false, width: 4.6cm),
    [`space-filling` / `cpk`],
  ),
  cell(
    crystal(prototypes.rocksalt("Na", "Cl", a: 5.64), legend: false, width: 4.6cm),
    [NaCl, `ball-and-stick`],
  ),
  cell(
    crystal(prototypes.rocksalt("Na", "Cl", a: 5.64), mode: "space-filling",
      legend: false, width: 4.6cm),
    [NaCl, `space-filling`],
  ),
  cell(
    molecule(benzene, view: v, bond-color: luma(110), legend: false, width: 4.6cm),
    [`bond-color: luma(110)`],
  ),
)
```

- [ ] **Step 2: Compile and render**

Run: `TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff examples && TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff images`
Expected: `examples/render-modes.pdf` compiles; `images/render-modes.png` is created. `git status --short wyckoff/images` shows ONLY the new `render-modes.png` (the other 9 stay byte-identical — a second run of the Task 2 control).

- [ ] **Step 3: VISUAL control — read the image**

Read `wyckoff/images/render-modes.png` and confirm, cell by cell:
1. ball-and-stick benzene: small carbon/hydrogen balls joined by two-tone sticks (grey/white halves) — today's look;
2. licorice: all sticks uniformly thicker, atoms reduced to caps the same thickness as the sticks (no fat balls) — a capped-stick ring;
3. space-filling benzene: large overlapping grey C spheres with white H bumps, **zero** visible sticks;
4. NaCl ball-and-stick vs 5. NaCl space-filling: the CPK cell shows big purple/green spheres touching along the cell axes (the classic rock-salt packing picture), cell box still visible at the silhouette;
6. bond-color benzene: same geometry as cell 1 but every stick a single uniform grey (no half-color split).
Aesthetic judgment call: if the licorice sticks look spindly or the caps visibly poke through stick joints, adjust ONLY the licorice `bond-width` auto default (0.25) and cap factor (0.55) in `figure.typ` — re-run Task 2 Step 6 afterwards (its zero-diff control must still hold, since licorice constants don't touch ball-and-stick).

- [ ] **Step 4: Document the modes in the README**

In `wyckoff/README.md`, after the section documenting `molecule()` (added in Stage 1), add:

```markdown
### Render modes

`crystal()`, `crystal-group()` and `molecule()` take a `mode:` option:

- `"ball-and-stick"` (default) — covalent-scale balls and two-tone sticks.
- `"space-filling"` (alias `"cpk"`) — spheres at the van der Waals radius,
  no bonds, no polyhedra; `radius:` scales the vdW radii (default 1.0).
- `"licorice"` — uniform thin sticks with matching end caps; atom size is
  independent of the element.

Bonds are split at the midpoint into two atom-coloured halves by default;
pass `bond-color: <color>` to draw each bond as a single stick in that color
instead (ball-and-stick and licorice).
```

(Match the surrounding heading level and code style of the existing README.)

- [ ] **Step 5: Run the full suite and commit**

Run: `TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff test`
Expected: `All tests passed!`

```bash
git add wyckoff/examples/render-modes.typ wyckoff/images/render-modes.png wyckoff/README.md
git commit -m "feat(wyckoff): render-modes showcase example + docs (#28)"
```

---

### Task 4: perspective camera in the scenery core (issue #29)

**Files:**
- Modify: `scenery/src/camera.typ` (full replacement below)
- Modify: `scenery/src/render.typ` (four call sites)
- Modify: `scenery/lib.typ` (export `project-scale`)
- Modify: `scenery/tests/test-camera.typ`
- Modify: `scenery/tests/test-render.typ`
- Create: `scenery/tests/errors/perspective-behind-camera.typ`

**Interfaces:**
- Produces (Typst, `camera.typ`):
  - `camera(azimuth: 25deg, elevation: 15deg, mode: "orthographic", distance: 25.0)` — `mode: "perspective"` selects the perspective branch; `distance` is the camera's world-unit distance from the view-space origin along the depth axis (only meaningful, and only stored, for perspective; asserted `> 0`). **The orthographic return dict is byte-identical to today's three-key dict** — `distance` is not stored on it.
  - `project(cam, point)` — unchanged `(sx, sy, depth)` dict. Perspective: `sx/sy` are the orthographic screen coordinates multiplied by `s = distance / (distance − depth)`; `depth` stays the unscaled view depth (same sort keys as orthographic). 2d and orthographic branches evaluate the exact same expressions as today.
  - **NEW** `project-scale(cam, depth)` — the screen-per-world magnification at camera depth `depth`: `distance / (distance − depth)` for perspective, the literal float `1.0` for orthographic and 2d. Asserts (perspective only) that the point is strictly in front of the camera, with an error message naming `distance`.
- Produces (Typst, `render.typ`): the four world-size→screen-size sites multiply by `project-scale` (all ×1.0 no-ops under orthographic):
  1. `_projected-sphere` (lines 215–218 today): occluder disk radius `r: sp.r * project-scale(camera, p.depth)`. This is the ONLY change the sphere depth-interval logic needs — `_line-sphere-occlusion`/`_depth-half` consume `sp.r` as given. (Known, documented approximation: under perspective the front-hemisphere refinement `aa + dh·dh` mixes screen units with view depth; occlusion is exact for orthographic and slightly conservative for mild perspective.)
  2. `_record` sphere branch (lines 514–521): drawn radius `p.r * project-scale(camera, <center depth>) * unit`.
  3. `_record` seg branch (line 527): stroke thickness scaled at the segment midpoint depth.
  4. `_record` arrow branch (lines 536–544): stroke thickness and head scale, at the arrow midpoint depth.
  `edge` widths are absolute page lengths (`0.7pt`), not world lengths — deliberately NOT scaled. `_projected-screen-bbox`/`_projected-width` need no change: they project AABB corners through `project`, which now carries the divide.
- Consumers downstream (wyckoff `figure.typ` bbox + `occlude`) are Task 5 — this task is self-contained to the scenery core.

- [ ] **Step 1: Write the failing camera tests**

In `scenery/tests/test-camera.typ`: change line 1 to
`#import "/src/camera.typ": camera, camera-2d, project, project-scale`
and append before the final `Camera OK` line:

```typ
// --- perspective camera (issue #29) ------------------------------------------

// The orthographic camera dict is BYTE-IDENTICAL to the pre-perspective shape:
// exactly three keys, no distance field. (The gallery gate depends on this.)
#assert.eq(
  camera(azimuth: 25deg, elevation: 15deg),
  (mode: "orthographic", azimuth: 25deg, elevation: 15deg),
)

// project-scale is the literal 1.0 for orthographic and 2d cameras.
#assert.eq(project-scale(cam0, 123.4), 1.0)
#assert.eq(project-scale(camera(azimuth: 25deg, elevation: 15deg), -7.0), 1.0)
#assert.eq(project-scale(camera-2d(), 0), 1.0)

// Pinned perspective math at az=el=0 (view-space == world: depth = y).
// s(depth) = distance / (distance - depth); a point at depth 5 with
// distance 10 doubles its screen offsets.
#let pcam = camera(azimuth: 0deg, elevation: 0deg, mode: "perspective", distance: 10)
#assert.eq(pcam.mode, "perspective")
#assert.eq(pcam.distance, 10)
#let near = project(pcam, (1.0, 5.0, 0.0))
#assert(calc.abs(near.sx - 2.0) < 1e-9, message: "near point must be magnified 2x")
#assert(calc.abs(near.depth - 5.0) < 1e-9,
  message: "depth key stays the unscaled view depth (sorting is unchanged)")
#assert(calc.abs(project-scale(pcam, 5.0) - 2.0) < 1e-9)
#let far = project(pcam, (1.0, -10.0, 0.0))
#assert(calc.abs(far.sx - 0.5) < 1e-9, message: "far point must shrink to 0.5x")
#assert(near.sx > far.sx, message: "nearer of two equal world offsets projects larger")
// distance -> orthographic limit
#let almost-ortho = project(camera(azimuth: 0deg, elevation: 0deg,
  mode: "perspective", distance: 1e9), (1.0, 5.0, 0.0))
#assert(calc.abs(almost-ortho.sx - 1.0) < 1e-6)

// REGRESSION PIN: orthographic projected values are unchanged by the new
// branch — the exact hand formula from the module docs.
#let q = project(camera(azimuth: 25deg, elevation: 15deg), (1.0, 2.0, 3.0))
#let x1 = 1.0 * calc.cos(25deg) + 2.0 * calc.sin(25deg)
#let y1 = -1.0 * calc.sin(25deg) + 2.0 * calc.cos(25deg)
#assert.eq(q, (
  sx: x1,
  sy: -y1 * calc.sin(15deg) + 3.0 * calc.cos(15deg),
  depth: y1 * calc.cos(15deg) + 3.0 * calc.sin(15deg),
))
```

(Note the last assert is exact dict equality — it pins that the orthographic branch returns a dict with the same keys, same order, same float values as the hand formula.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make pkgroot && TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C scenery test`
Expected: FAIL — `camera.typ` exports no `project-scale` (unresolved import).

- [ ] **Step 3: Implement the camera**

Replace `scenery/src/camera.typ` in full:

```typ
// Camera + projection for the scene core.
// Pure functions, no cetz dependency: a camera is a plain dictionary and
// `project` maps a 3-point to screen coordinates plus a depth value.

/// Creates a camera.
///
/// The view frame is pinned (see `project`): with `azimuth == elevation == 0deg`
/// the view looks along $+y$ with $+x$ to the right and $+z$ up; depth grows
/// toward the viewer.
///
/// - azimuth (angle): Rotation about the vertical axis.
/// - elevation (angle): Tilt above the horizontal plane.
/// - mode (str): `"orthographic"` (default) or `"perspective"`.
/// - distance (float): Perspective only — the camera's world-unit distance
///   from the view-space origin along the depth axis. Smaller = stronger
///   foreshortening; must exceed the scene's greatest depth. Ignored (and not
///   stored) for orthographic cameras, so the orthographic camera dictionary
///   is identical to earlier versions.
/// -> camera
#let camera(azimuth: 25deg, elevation: 15deg, mode: "orthographic", distance: 25.0) = {
  assert(mode in ("orthographic", "perspective"),
    message: "camera mode must be \"orthographic\" or \"perspective\", got " + repr(mode))
  if mode == "perspective" {
    assert(type(distance) in (int, float) and distance > 0,
      message: "perspective camera distance must be a positive number, got " + repr(distance))
    (mode: "perspective", azimuth: azimuth, elevation: elevation, distance: distance)
  } else {
    (mode: "orthographic", azimuth: azimuth, elevation: elevation)
  }
}

/// Creates a 2D identity camera.
///
/// Flat diagrams share the 3D pipeline: `project` passes $(x, y, z)$ straight
/// through to `(sx: x, sy: y, depth: 0)`.
/// -> camera
#let camera-2d() = (mode: "2d")

/// The screen-per-world scale factor at camera depth `depth`: how much a world
/// length placed at that depth is magnified on screen.
///
/// Orthographic and 2d cameras return exactly `1.0` — world radii ARE screen
/// radii there, and every pre-perspective consumer relies on that identity.
/// A perspective camera returns `distance / (distance - depth)`, which is how
/// a world radius `r` at that depth maps to screen: `r * project-scale(..)`.
///
/// - cam (camera): The camera.
/// - depth (float): A camera depth as returned by `project(..).depth`.
/// -> float
#let project-scale(cam, depth) = {
  if cam.mode != "perspective" { return 1.0 }
  let denom = cam.distance - depth
  assert(denom > 1e-9 * cam.distance,
    message: "scenery: point at camera depth " + repr(depth)
      + " is at or behind the perspective camera (distance: " + repr(cam.distance)
      + "); increase the camera's distance")
  cam.distance / denom
}

/// Projects a 3-point to screen coordinates plus depth.
///
/// For an orthographic camera the pinned convention is
/// $x_1 = x cos("az") + y sin("az")$, $y_1 = -x sin("az") + y cos("az")$,
/// $"sx" = x_1$, $"sy" = -y_1 sin("el") + z cos("el")$,
/// $"depth" = y_1 cos("el") + z sin("el")$.
///
/// A perspective camera multiplies `sx`/`sy` by `project-scale(cam, depth)`
/// (divide-by-depth); `depth` itself stays the unscaled view depth, so depth
/// sorting is identical across the two 3D modes.
///
/// For a 2D camera the point passes through as `(sx: x, sy: y, depth: 0)`.
///
/// - cam (camera): The camera to project through.
/// - point (vector): The 3-point $(x, y, z)$ to project.
/// -> dictionary
#let project(cam, point) = {
  let (x, y, z) = point
  if cam.mode == "2d" {
    return (sx: x, sy: y, depth: 0)
  }
  let az = cam.azimuth
  let el = cam.elevation
  let x1 = x * calc.cos(az) + y * calc.sin(az)
  let y1 = -x * calc.sin(az) + y * calc.cos(az)
  let sy = -y1 * calc.sin(el) + z * calc.cos(el)
  let depth = y1 * calc.cos(el) + z * calc.sin(el)
  if cam.mode == "perspective" {
    let s = project-scale(cam, depth)
    return (sx: x1 * s, sy: sy * s, depth: depth)
  }
  (sx: x1, sy: sy, depth: depth)
}
```

- [ ] **Step 4: Apply the audit fixes in `render.typ`**

Four edits in `scenery/src/render.typ`:

1. Line 17, extend the import:
```typ
#import "camera.typ": project, project-scale
```

2. Replace `_projected-sphere` (lines 215–218):
```typ
#let _projected-sphere(sp, camera) = {
  let p = project(camera, sp.center)
  // Screen-space occluder disk. Under perspective a sphere's silhouette radius
  // depends on its depth; project-scale is exactly 1.0 for orthographic/2d.
  (sx: p.sx, sy: p.sy, depth: p.depth, r: sp.r * project-scale(camera, p.depth))
}
```

3. In `_record`, replace the sphere/seg/arrow branches (keep face/label/else exactly as they are):
```typ
  if k == "sphere" {
    let q = project(camera, p.center)
    (
      kind: k,
      pos: (q.sx * unit, q.sy * unit),
      radius: p.r * project-scale(camera, q.depth) * unit,
      color: st.color,
      stroke: (paint: st.color.darken(st.stroke-darken), thickness: st.stroke-width),
    )
  } else if k == "seg" {
    (
      kind: k,
      a: _screen(camera, unit, p.a),
      b: _screen(camera, unit, p.b),
      stroke: (
        paint: st.color,
        thickness: st.w * project-scale(camera, project(camera, _mid(p.a, p.b)).depth) * unit * 1cm,
        cap: "round",
      ),
    )
  } else if k == "edge" {
    (
      kind: k,
      a: _screen(camera, unit, p.a),
      b: _screen(camera, unit, p.b),
      stroke: (paint: st.color, thickness: st.width),
    )
  } else if k == "arrow" {
    let wsc = project-scale(camera, project(camera, _mid(p.from, p.to)).depth)
    (
      kind: k,
      a: _screen(camera, unit, p.from),
      b: _screen(camera, unit, p.to),
      stroke: (paint: st.color, thickness: st.w * wsc * unit * 1cm, cap: "round"),
      mark: if p.at("draw-head", default: true) {
        (end: st.head, fill: st.color, scale: st.head-scale * st.w * wsc * unit)
      } else { none },
    )
  } else if k == "face" {
```
(`edge` is unchanged — its `width` is an absolute page length, not a world length. `seg`/`arrow` widths ARE world lengths (`w` in scene units), so a licorice stick and its cap sphere must scale together under perspective; the tiny per-half width difference of a split two-tone bond under mild perspective (<3% at distance 25) is accepted.)

4. Add a doc note under the `_line-sphere-occlusion` comment block (lines 211–214), appending one line to the existing comment:
```typ
// Under a perspective camera the projected disk uses the depth-scaled radius
// (via _projected-sphere); the front-hemisphere refinement mixes screen units
// with view depth and is exact for orthographic, approximate (conservative)
// for mild perspective.
```

- [ ] **Step 5: Export `project-scale` and add the render tests**

In `scenery/lib.typ`, change the camera import line to:
```typ
#import "src/camera.typ": camera, camera-2d, project, project-scale
```

In `scenery/tests/test-render.typ`: extend the render import (line 5) with `, _projected-sphere` and append before the `Render sort OK` line:

```typ
// --- perspective: projected sphere radius scales with depth -------------------
#let pcam = camera(azimuth: 0deg, elevation: 0deg, mode: "perspective", distance: 10)
#let near-sp = _projected-sphere((kind: "sphere", center: (0, 5, 0), r: 1.0), pcam)
#assert(calc.abs(near-sp.r - 2.0) < 1e-9, message: "near sphere silhouette doubles")
#let far-sp = _projected-sphere((kind: "sphere", center: (0, -10, 0), r: 1.0), pcam)
#assert(calc.abs(far-sp.r - 0.5) < 1e-9, message: "far sphere silhouette halves")
#assert(near-sp.r > far-sp.r, message: "nearer sphere must project larger")
// negative control: the orthographic occluder radius is untouched
#assert.eq(_projected-sphere((kind: "sphere", center: (0, 5, 0), r: 1.0), cam0).r, 1.0)
```

Create `scenery/tests/errors/perspective-behind-camera.typ`:

```typ
// expected: at or behind the perspective camera
#import "/lib.typ": camera, project
#let cam = camera(mode: "perspective", distance: 2.0)
#let _ = project(cam, (0.0, 100.0, 0.0))
```

- [ ] **Step 6: Run the scenery suite (the byte-identity gate)**

Run: `TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C scenery test`
Expected: `All tests passed!` — including (a) every PRE-EXISTING assert in test-camera/test-render (notably `flat == (sx: 3, sy: 4, depth: 0)`, the `_clip-lines` fragment positions, and `broad-phase-arrow == bare-arrow` exact prim equality — the orthographic byte-identity controls), (b) the new perspective asserts, and (c) the new error test (`== tests/errors/perspective-behind-camera.typ (expected error)`).

- [ ] **Step 7: Cross-package regression + zero-diff pixel control**

Run: `make test`
Expected: `All package test suites passed!` (wyckoff and brillouin consume the edited core through `_pkgroot`).

Run:

```bash
TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C scenery images
TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C brillouin images
git status --short scenery/images brillouin/images
```

Expected: the only entry is the pre-existing untracked `scenery/images/c60.png` (see Global Constraints) — **no tracked PNG modified**. This is the pixel-level proof that the audit's ×`project-scale` sites are exact no-ops for every orthographic scene.

- [ ] **Step 8: Commit**

```bash
git add scenery/src/camera.typ scenery/src/render.typ scenery/lib.typ scenery/tests/test-camera.typ scenery/tests/test-render.typ scenery/tests/errors/perspective-behind-camera.typ
git commit -m "feat(scenery): perspective camera mode + project-scale radius audit (#29)"
```

---

### Task 5: perspective in the wyckoff consumers + example (issue #29)

**Files:**
- Modify: `wyckoff/src/figure.typ` (camera construction, screen bbox, `occlude`)
- Create: `wyckoff/tests/test-perspective.typ`
- Create: `wyckoff/examples/perspective.typ`
- Create + commit: `wyckoff/images/perspective.png`
- Modify: `wyckoff/README.md`

**Interfaces:**
- Produces (Typst): the wyckoff `view:` dict gains two optional keys, threaded into `scenery.camera`: `view: (azimuth:, elevation:, mode: "perspective", distance: <Å>)`. Defaults `(mode: "orthographic", distance: 25.0)` — orthographic callers get the byte-identical three-key camera dict (Task 4 guarantee). No `crystal()`/`molecule()` signature change: the view dict carries it.
- Fixes the two remaining world-radius-in-screen-units sites from the design doc's audit list:
  1. `build-scene`'s screen bbox (`figure.typ` lines 103–106 today): `sx ± r` becomes `sx ± r·project-scale(cam, depth)`.
  2. `occlude()` (lines 172–198): the sphere disk radius `r` and the bond stroke width `w` become their depth-scaled screen values. The **depth slacks** (`sp.depth + 2·sp.r`, `sp.depth + sp.r`, `b.depth + 1.0`) also consume the scaled `r`/`w` — under orthographic all values are ×1.0-identical (the controller ruling of issue #8 is preserved bit-for-bit), and under perspective the heuristic stays a heuristic with self-consistent screen quantities.
- One documented approximation: the polyhedra `face-offset` comment ("screen x/y are invariant") holds exactly only for orthographic; under perspective the 0.01 depth push changes screen positions by ~0.01/distance (≈0.04% at the default distance) — visually nil, noted in the comment.
- Consumes: `scenery.project-scale` (Task 4), Task 2's `build-scene` shape.

- [ ] **Step 1: Write the failing tests**

Create `wyckoff/tests/test-perspective.typ`:

```typ
#import "/src/structure.typ": structure
#import "/src/figure.typ": build-scene, occlude, render

#let nacl = structure(
  spacegroup: 225, lattice: (a: 5.64),
  sites: ((element: "Na", wyckoff: "a"), (element: "Cl", wyckoff: "b")),
)

// Orthographic scenes are UNCHANGED by the perspective plumbing: an explicit
// orthographic view is prim-for-prim and bbox-for-bbox equal to the default.
#let v = (azimuth: 30deg, elevation: 15deg)
#let plain = build-scene(nacl, view: v)
#let explicit = build-scene(nacl, view: (..v, mode: "orthographic"))
#assert.eq(plain.prims, explicit.prims)
#assert.eq(plain.bbox, explicit.bbox)
#assert.eq(plain.camera, (mode: "orthographic", azimuth: 30deg, elevation: 15deg))

// Perspective camera is threaded through the view dict.
#let pv = (azimuth: 30deg, elevation: 15deg, mode: "perspective", distance: 20.0)
#let per = build-scene(nacl, view: pv)
#assert.eq(per.camera.mode, "perspective")
#assert.eq(per.camera.distance, 20.0)

// World-space primitives are IDENTICAL (radii stay world radii; perspective
// enters only at projection time: bbox, occlude, and the renderer).
#assert.eq(per.prims, plain.prims)

// The screen bbox is not: near-side magnification widens it.
#assert(per.bbox.at(2) - per.bbox.at(0) > plain.bbox.at(2) - plain.bbox.at(0),
  message: "perspective must widen the screen bbox (near side magnified)")

// occlude() still suppresses covered bond stubs under perspective (the
// coverage heuristic runs on self-consistent screen quantities).
#let kept = occlude(per.prims, per.camera)
#assert(kept.filter(p => p.kind == "seg").len() < per.prims.filter(p => p.kind == "seg").len(),
  message: "coverage suppression must still fire under perspective")
// ... and is bit-for-bit unchanged for the orthographic scene.
#assert.eq(occlude(plain.prims, plain.camera), occlude(explicit.prims, explicit.camera))

// End-to-end compile smoke: a perspective figure renders.
#render(per, width: 6cm, legend: false)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff test`
Expected: FAIL — `per.camera.mode` is `"orthographic"` (`assert.eq` mismatch): `build-scene` ignores `view.mode` because the camera is constructed from azimuth/elevation only (`figure.typ` line 36 today).

- [ ] **Step 3: Thread the camera mode and fix the two audit sites**

Three edits in `wyckoff/src/figure.typ`:

1. Replace the camera construction (inside `build-scene`, currently `let cam = scenery.camera(azimuth: az, elevation: elev)`):
```typ
  let cam = scenery.camera(
    azimuth: az, elevation: elev,
    mode: view.at("mode", default: "orthographic"),
    distance: view.at("distance", default: 25.0),
  )
```
and extend the `face-offset` comment block with one line:
```typ
  // (Exact for orthographic; under perspective the 0.01 depth push shifts
  // screen x/y by ~0.01/distance — visually negligible.)
```

2. Replace the sphere branch of the screen-bbox loop (currently `xs += (s.sx - p.r, s.sx + p.r)` / `ys += ...`):
```typ
    if p.kind == "sphere" {
      let s = scenery.project(cam, p.center)
      // Screen radius: world radius times the camera's depth magnification
      // (exactly 1.0 for orthographic — wyckoff pixel parity).
      let rs = p.r * scenery.project-scale(cam, s.depth)
      xs += (s.sx - rs, s.sx + rs)
      ys += (s.sy - rs, s.sy + rs)
    } else if p.kind == "face" {
```

3. In `occlude`, replace the two projected-collection builders (keep `seg-hidden`/`covered`/the filter loop verbatim):
```typ
  let spheres = prims.filter(p => p.kind == "sphere").map(p => {
    let q = scenery.project(cam, p.center)
    // Disk radius in screen units (depth-scaled; x1.0 under orthographic).
    (c: (q.sx, q.sy), r: p.r * scenery.project-scale(cam, q.depth), depth: q.depth)
  })
  let segs = prims.filter(p => p.kind == "seg").map(p => {
    let d = _pdepth(cam, _mid(p.a, p.b))
    (a: _proj2(cam, p.a), b: _proj2(cam, p.b),
     w: p.w * scenery.project-scale(cam, d), depth: d)
  })
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff test`
Expected: `tests/test-perspective.typ` passes AND every pre-existing wyckoff test still passes (test-scene's 27/108/96 counts and bbox ordering are the orthographic no-op control); suite ends `All tests passed!`.

- [ ] **Step 5: Zero-diff pixel control (orthographic images untouched)**

```bash
TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff images
git status --short wyckoff/images
```

Expected: **no output**. Every committed wyckoff example is orthographic; if any PNG moved, an audit site is not a ×1.0 no-op — fix before committing.

- [ ] **Step 6: Add the perspective example**

Create `wyckoff/examples/perspective.typ`:

```typ
#import "/lib.typ": crystal, prototypes

#set page(width: auto, height: auto, margin: 0.6cm)
#set text(font: "New Computer Modern", size: 10pt)

// The same 2x2x1 NaCl supercell through both cameras. Under perspective the
// near corner's atoms are visibly larger and the cell edges converge.
#let nacl = prototypes.rocksalt("Na", "Cl", a: 5.64)

#grid(
  columns: 2,
  column-gutter: 1cm,
  align(center)[
    #crystal(nacl, supercell: (2, 2, 1), legend: false, width: 6.5cm)
    Orthographic (default)
  ],
  align(center)[
    #crystal(nacl, supercell: (2, 2, 1),
      view: (azimuth: 25deg, elevation: 15deg, mode: "perspective", distance: 18),
      legend: false, width: 6.5cm)
    Perspective (`distance: 18`)
  ],
)
```

(Depth check, hand-worked: the supercell's deepest corner (11.28, 11.28, 5.64) has view depth ≈ 6.7 Å, so `distance: 18` gives a magnification range ≈ 0.80–1.60× — a clearly visible but undistorted effect, safely in front of the camera.)

Run: `TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff examples && TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff images`
Expected: `examples/perspective.pdf` compiles; `git status --short wyckoff/images` shows ONLY the new `perspective.png`.

- [ ] **Step 7: VISUAL control — read the image**

Read `wyckoff/images/perspective.png`. Proof of the feature: in the right panel, (a) spheres of the same element are NOT all the same size — front-lower-left atoms are distinctly larger than back atoms of the same color (in the left panel they are identical); (b) the four cell-box edges running into depth visibly converge instead of staying parallel; (c) no artifacts: bonds still meet spheres cleanly, no stray bond stubs floating where `occlude` should have suppressed them, legend/margins uncorrupted.

- [ ] **Step 8: Document the perspective view in the README**

In `wyckoff/README.md`, in/near the section documenting `view:` (or after the render-modes section from Task 3), add:

```markdown
### Perspective camera

The `view:` dictionary accepts `mode: "perspective"` with a `distance:` in
Ångström (the camera's distance from the scene origin; smaller = stronger
foreshortening, default 25):

    #crystal(s, view: (azimuth: 25deg, elevation: 15deg,
      mode: "perspective", distance: 18))

The default remains orthographic and is pixel-identical to earlier versions.
```

- [ ] **Step 9: Full suite + commit**

Run: `make test`
Expected: `All package test suites passed!`

```bash
git add wyckoff/src/figure.typ wyckoff/tests/test-perspective.typ wyckoff/examples/perspective.typ wyckoff/images/perspective.png wyckoff/README.md
git commit -m "feat(wyckoff): perspective view threading + screen-radius audit fixes (#29)"
```

---

### Task 6: shading polish + full gallery rebaseline (issue #30)

**Files:**
- Modify: `scenery/src/render.typ` (`_sphere-gradient`, lines 40–47 today; `_record` sphere branch; draw loop line 654)
- Modify: `scenery/src/style.typ` (`default-theme.sphere` gains `specular: true`)
- Modify: `scenery/tests/test-render.typ` (gradient pin tests)
- Regenerate + commit: `wyckoff/images/*.png` (11 files after Tasks 3/5), `scenery/images/{flow,hero,primitives,solids,visibility}.png`, `brillouin/images/*.png` (3 files)

**Interfaces:**
- Produces (Typst): `_sphere-gradient(col, specular: true)`:
  - `specular: true` (**default — the repaint is intended**): a five-stop gradient adding a tight near-white specular core and a slightly deeper rim:
    ```typ
    gradient.radial(
      (color.mix((white, 92%), (col, 8%)), 0%),    // specular core
      (color.mix((white, 70%), (col, 30%)), 12%),  // old 0% highlight, pushed out
      (_sphere-fill(col), 30%),                    // UNCHANGED issue-#8 mid-tone
      (col, 58%),
      (col.darken(35%), 100%),                     // slightly deeper rim
      center: (35%, 30%),
      radius: 110%,
    )
    ```
  - `specular: false`: the EXACT pre-Stage-3 four-stop gradient (old look preserved verbatim as an opt-out — pinned by test).
  - `_sphere-fill` is **untouched**: it remains the mid stop, so the issue-#8 mid-tone guard in `scenery/tests/test-render.typ:255-266` passes unchanged — the "old mid-tone assertion" survives because the mid-tone itself survives; only its stop position moves (25%→30%).
  - Theme/opt-out plumbing: `default-theme.sphere.specular: true`; `_record`'s sphere branch carries `specular: st.at("specular", default: true)`; the draw loop calls `_sphere-gradient(r.color, specular: r.specular)`. So both a theme override and a per-sphere hook (`sphere(.., specular: false)`) restore the classic look. `annotate.typ`'s legend keeps calling `_sphere-gradient(r.color)` — swatches pick up the specular by default and stay consistent with the balls.
  - **Why default-on:** the design doc treats the repaint as this stage's intended outcome and budgets the rebaseline as the milestone's main gate cost; default-off would ship the polish invisible-by-default and push the same rebaseline onto whichever release finally flips it. The graceful degradation the doc asks for is the pinned `specular: false` opt-out.
  - **Outline decision:** spheres already carry a thin darkened outline (`_record`: `st.color.darken(st.stroke-darken)` at `st.stroke-width`, themeable per-primitive). No new outline API is added — the "optional thin outline" is the existing `stroke-width`/`stroke-darken` hooks, now documented next to `specular`. Bond-cylinder gradient shading is NOT attempted: cetz strokes take a single paint, and licorice's round caps + two-tone split already carry the depth cues. (Both calls are flagged in the Self-Review for adjudication.)
- **Rebaseline contract:** this task repaints every figure containing a sphere. All committed example PNGs in all three packages are regenerated in one commit, after an image-by-image review against before-copies. This is the "Pixel-identical gallery gate — rebaseline required" item from the design doc: the diff is expected and must not be rubber-stamped — a shading change can mask a real geometry regression, so the review checklist below is mandatory.

- [ ] **Step 1: Snapshot the before-images**

```bash
SCRATCH=/private/tmp/claude-501/-Users-liujinguo-tcode-scenery/90c1ab17-f03e-4e6f-a82a-63358253144c/scratchpad
mkdir -p $SCRATCH/rebaseline-before/{wyckoff,scenery,brillouin}
cp wyckoff/images/*.png $SCRATCH/rebaseline-before/wyckoff/
cp scenery/images/*.png $SCRATCH/rebaseline-before/scenery/
cp brillouin/images/*.png $SCRATCH/rebaseline-before/brillouin/
```

Expected: 11 + 6 + 3 files copied (the scenery copy includes the untracked c60.png; ignore it below).

- [ ] **Step 2: Write the failing gradient tests**

In `scenery/tests/test-render.typ`, extend the render import (line 5) with `, _sphere-gradient` and append after the existing `_sphere-fill` guard block (after line 266, before `Render sort OK`):

```typ
// --- sphere gradient: specular stop (issue #30) --------------------------------
// specular: false must reproduce the classic pre-specular gradient EXACTLY —
// the graceful-degradation opt-out the M4 design doc requires.
#assert.eq(
  _sphere-gradient(col, specular: false),
  gradient.radial(
    (color.mix((white, 70%), (col, 30%)), 0%),
    (_sphere-fill(col), 25%),
    (col, 55%),
    (col.darken(30%), 100%),
    center: (35%, 30%),
    radius: 110%,
  ),
  message: "specular: false must be the exact classic gradient",
)
// The default gradient gains the specular core: five stops, a first stop
// strictly lighter than the classic highlight, and the issue-#8 mid-tone
// _sphere-fill(col) still present as a stop.
#let spec-stops = _sphere-gradient(col).stops()
#assert.eq(spec-stops.len(), 5, message: "specular gradient has five stops")
#assert.eq(spec-stops.first().at(0), color.mix((white, 92%), (col, 8%)))
#assert(spec-stops.map(s => s.at(0)).contains(_sphere-fill(col)),
  message: "the issue-#8 mid-tone must survive as a stop of the new gradient")
#assert(_sphere-gradient(col) != _sphere-gradient(col, specular: false),
  message: "default gradient must actually differ (the repaint is intended)")
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C scenery test`
Expected: FAIL — `_sphere-gradient` takes no `specular` argument (`unexpected argument: specular`).

- [ ] **Step 4: Implement the shading**

1. In `scenery/src/render.typ`, replace `_sphere-gradient` (lines 40–47):

```typ
/// Radial "3D ball" gradient for a sphere of base colour `col`. With
/// `specular: true` (the default): a tight near-white specular core fading
/// through the classic highlight and the `_sphere-fill` body tint to a
/// darkened rim. `specular: false` reproduces the pre-specular four-stop
/// gradient exactly (the classic look, selectable per sphere or per theme via
/// the `specular` style hook). The sphere's thin outline is separate: the
/// theme's `stroke-width`/`stroke-darken` hooks on the drawn circle.
///
/// - col (color): The sphere's base colour.
/// - specular (bool): Add the specular highlight stop (default) or keep the
///   classic gradient.
/// -> gradient
#let _sphere-gradient(col, specular: true) = if specular {
  gradient.radial(
    (color.mix((white, 92%), (col, 8%)), 0%),
    (color.mix((white, 70%), (col, 30%)), 12%),
    (_sphere-fill(col), 30%),
    (col, 58%),
    (col.darken(35%), 100%),
    center: (35%, 30%),
    radius: 110%,
  )
} else {
  gradient.radial(
    (color.mix((white, 70%), (col, 30%)), 0%),
    (_sphere-fill(col), 25%),
    (col, 55%),
    (col.darken(30%), 100%),
    center: (35%, 30%),
    radius: 110%,
  )
}
```

2. In `_record`'s sphere branch (as rewritten in Task 4), add one field after `color: st.color,`:
```typ
      specular: st.at("specular", default: true),
```

3. In the `scene-group` draw loop, change the sphere line (line 654 today) to:
```typ
      circle(r.pos, radius: r.radius, fill: _sphere-gradient(r.color, specular: r.specular), stroke: r.stroke)
```

4. In `scenery/src/style.typ`, add to `default-theme.sphere` (after `stroke-width: 0.5pt,`):
```typ
    specular: true, // specular highlight stop in the ball gradient (issue #30)
```

- [ ] **Step 5: Run all suites**

Run: `make test`
Expected: `All package test suites passed!` — the scenery gradient pins pass; the untouched `_sphere-fill` guard still passes; wyckoff/brillouin compile (their look changes, but no test asserts pixel content — the committed PNGs are the pixel gate, handled next).

- [ ] **Step 6: Regenerate every baseline**

```bash
TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C scenery images
TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff images
TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C brillouin images
git status --short scenery/images wyckoff/images brillouin/images
```

Expected: **every tracked PNG modified** — 5 scenery + 11 wyckoff + 3 brillouin = 19 modified files (plus the untracked c60.png, which stays untracked). A tracked PNG that did NOT change would itself be suspicious (a sphere-free figure is the only legitimate reason).

- [ ] **Step 7: MANDATORY image-by-image review (the gate, not a formality)**

For EACH of the 19 tracked images, Read the before-copy (Step 1 scratchpad path) and the new file side by side and check:
1. **Only shading changed:** every ball now shows a small bright (near-white) highlight up-left of center and a slightly deeper rim. The mid-body color is visually unchanged (same `_sphere-fill` tint).
2. **Geometry identical:** atom positions, sphere sizes, bond endpoints, cell edges, polyhedra outlines, label positions, legend rows, triad arrows, page dimensions — all unmoved. Any shifted or missing element is a REAL regression hiding behind the repaint: stop and bisect (the shading commit touches no geometry, so any geometry diff came from Tasks 2–5 and escaped their zero-diff controls).
3. **Legend consistency:** legend swatches carry the same specular look as the scene balls (`annotate.typ` shares the gradient).
4. Aesthetic check on `wyckoff/images/gallery.png` and `render-modes.png` specifically: the specular core must read as a glint, not a white hole — if it looks blown out on pale elements (H, S), tighten the first stop toward `12%` position or reduce the white share to `88%`, re-run Steps 5–6, and note the adjustment in the commit message.

Record a one-line verdict per image in the task notes (e.g. `nacl.png: highlight+rim only, geometry identical — OK`).

- [ ] **Step 8: Commit the shading + rebaseline together**

```bash
git add scenery/src/render.typ scenery/src/style.typ scenery/tests/test-render.typ \
  scenery/images/flow.png scenery/images/hero.png scenery/images/primitives.png \
  scenery/images/solids.png scenery/images/visibility.png \
  wyckoff/images brillouin/images
git commit -m "feat(scenery): specular highlight in sphere shading + gallery rebaseline (#30)

Repaints every committed example image (reviewed image-by-image: shading-only
diff, geometry identical). specular: false preserves the exact classic look."
```

(Note: `git add wyckoff/images brillouin/images` is safe — every file there is tracked; `scenery/images` is added file-by-file to keep the untracked `c60.png` out.)

- [ ] **Step 9: Final verification**

Run: `make test && git status --short`
Expected: `All package test suites passed!`; remaining dirt is exactly the pre-existing out-of-scope files (`AGENTS.md`, `.DS_Store` ×2, `scenery/README.md`, `scenery/examples/c60.typ`, `scenery/images/c60.png` — untouched by this stage).

---

## Self-Review

**Spec coverage (issues #27–#30 / design doc "Visualization changes", "Data changes", "Testing & gates"):**
- #27: `r-vdw` from the verified pymatgen attribute (`Element.van_der_waals_radius`, present in the installed pymatgen 2026.5.4, `FloatWithUnit` Å or `None`), design-doc fallback `1.5 × r-atom` (explicitly not raw r-atom), float + sanity asserts (O 1.52, C 1.70) in both the generator and `test-data.typ`, regenerated json committed, `element-info` exposure → Task 1. ✓
- #28: `mode:` on all three entry points with a pinned per-mode radius/bond table (b&s exact-current, cpk = 1.0×r-vdw no bonds/polyhedra, licorice = uniform 0.55×bond-width caps + untrimmed 0.25-wide sticks), `cpk` alias, `bond-color:` single-color opt-out drawing ONE seg per bond, showcase example (benzene ×4 + NaCl ×2) with a concrete visual checklist, README docs → Tasks 2–3. ✓
- #29: `camera(mode: "perspective", distance:)` with pinned math (`s = d/(d−depth)`, unscaled depth key), behind-camera error test; the audit implemented via ONE mechanism (`project-scale`, exported) applied at all six world-radius×screen-unit sites named by the design doc — `render.typ` `_projected-sphere` (which feeds the whole `_depth-half`/interval machinery), `_record` sphere/seg/arrow, `figure.typ` bbox, `occlude` disks + stroke widths; orthographic-unchanged tests at value level (exact dict/prim equality) AND pixel level (zero-diff regen of all three packages' images); nearer-projects-larger tests at camera, occluder, and scene-bbox levels → Tasks 4–5. ✓
- #30: specular stop default-on with justification (design doc treats the repaint as intended; the doc's "degrade gracefully" option is the pinned `specular: false` exact-classic branch, reachable per-theme and per-sphere); the issue-#8 mid-tone assertion survives untouched because `_sphere-fill` stays the mid stop (called out explicitly); ALL 19 tracked baselines regenerated + committed with a mandatory per-image review protocol distinguishing shading diff from geometry regression → Task 6. ✓

**Ordering:** vdW (1) before CPK (2–3); perspective (4–5) independent of modes but placed before the repaint; shading + rebaseline (6) strictly last so it repaints the new render-modes/perspective images exactly once. Each task is independently committable; every commit line lists explicit paths to dodge the repo's pre-existing untracked dirt.

**Pixel-gate architecture:** three layers of defense before the intentional Task 6 repaint — (a) Task 2 Step 1 pre-flight proves baselines are fresh (or halts); (b) data-level exact equality (`default == ball-and-stick` prims, ortho == default view prims/bbox/occlude, exact `project` dict pins, untouched test-scene/test-camera asserts as negative controls); (c) pixel-level zero-diff PNG regeneration at the end of Tasks 2, 3, and 5. The ×1.0 identity is trustworthy because `project-scale` returns the literal float `1.0` and IEEE `x * 1.0 == x` for finite floats; the only type nuance (an int sphere radius becoming float) is confined to `_projected-sphere`/`_record` outputs, which no test compares by type and whose committed scenes all use float radii.

**Placeholder scan:** every step ships complete code (generator diff, full `build-scene` head + bond loop, full `crystal.typ`, full `camera.typ`, all four `render.typ` branch replacements, both `figure.typ` audit sites, the gradient with both stop lists, all tests with exact asserts, both examples, README text, exact commands with expected outputs). The only judgment-deferred values are aesthetic constants (licorice 0.25/0.55, specular 92%/12%, distance 18 in the example), each with an explicit adjustment procedure and the invariant it must not break.

**Known risks / adjudication flags carried forward:**
- `gradient.stops()` and gradient `==` equality are relied on by the Task 6 pins; if either is unsupported in Typst 0.14.2, fall back to comparing the two constructor expressions componentwise (the assert message names the intent).
- The perspective `distance: 25.0` default is a compromise (safe for unit-cell-scale scenes, weak effect); scenes deeper than the distance fail loudly via the behind-camera assert rather than rendering garbage.
- Perspective line-sphere occlusion and face culling are documented approximations (exact for orthographic); accepted for mild perspective, revisitable in Stage 4's Rust engine.
- The two-tone bond halves get per-half width scaling under perspective (<3% mismatch at the joint at default distance) — accepted and noted in Task 4.
- scenery's manual and README (currently dirty in the working tree) are deliberately not edited; wyckoff's README carries the user-facing docs for modes and perspective.
