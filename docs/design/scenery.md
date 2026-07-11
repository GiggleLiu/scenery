# scenery — Product Design

**Date:** 2026-07-11
**Status:** Approved product design (this doc is the contract for issue slicing / planning)
**Repo:** `GiggleLiu/scenery` (monorepo; each package published separately to Typst Universe)

## Need

Scientists writing papers, lectures, and slides in Typst cannot produce many kinds of
publication-quality scientific figures natively. Typst Universe has plotting (lilaq),
drawing (cetz), and diagrams (fletcher/quill), but **no 3D capability at all and no
dedicated tools** for crystal structures, Brillouin zones/band paths, tensor networks,
lattice/spin models, complex-function visualization, phase portraits, polyhedra/tilings,
ray optics, or Feynman diagrams. Today these figures are imported as static images from
Python/Mathematica, breaking fonts, theming, vector quality, and reproducibility.

This project builds **one monorepo: the missing scientific-visualization layer of Typst
Universe** — a single shared **scene core** (typed primitives → transforms/projection →
depth sort → styled CeTZ rendering, generalizing the proven `wyckoff` engine to 2D and
3D) plus thin domain packages on top, each published separately to Universe.

**Admission rules** for any package in the family:
1. No existing Universe package does the same thing (verified against the live index).
2. Demonstrable community need.
3. Built on the shared core, not ad-hoc drawing.

**Users:** scientists/mathematicians writing papers, theses, lecture notes, and slides in
Typst; initially the condensed-matter/quantum community, broadening with later waves.

**Success criteria (~6 months):** community adoption — packages published on Universe
with quill/diagraph-tier traction (~100+ GitHub stars, external issues/contributors).

**Constraints:**
- Pure Typst runtime (zero build toolchain for users and contributors); the core's data
  layer stays plugin-ready so a WASM accelerator can be added later without API change.
- Runtime dependency: cetz only.
- Heavy/data-driven inputs are pre-generated offline (Python → JSON), the wyckoff pattern.
- `wyckoff` migrates into this monorepo immediately (before its Universe submission) and
  becomes the core's first consumer.

## Prior art & landscape

Survey of the full Universe index (1,432 packages, fetched 2026-07-11).

**Baseline (exists, mature — we do NOT compete):** cetz 1,784★ (drawing), fletcher
1,076★ (arrow diagrams), lilaq 799★ (2D plotting), cetz-plot 277★, diagraph 151★
(Graphviz auto-layout), quill 107★ (quantum circuits).

**Confirmed gaps (nothing dedicated exists):**

| Domain | Nearest neighbor | Verdict |
|---|---|---|
| Programmatic 3D scenes | maquette (mesh-file converter only), plotsy-3d 107★ (surface plots only), **cetz-plot has zero 3D** | **clean gap** |
| Crystal structures | — (wyckoff fills it) | clean gap |
| Brillouin zones / k-paths / band panels | energy-dia (energy *levels* only) | **clean gap** |
| Tensor network diagrams | — | clean gap |
| Lattice/spin-model diagrams | qec-thrust (stabilizer codes only) | clean gap |
| Complex-function viz (domain coloring) | — | clean gap (needs per-pixel) |
| ODE phase portraits / streamlines | lilaq quiver (fields only, no integration) | clean gap |
| Polyhedra / tilings / nets | ctz-euclide (2D constructions) | clean gap |
| Textbook ray optics | beam/laserly (bench schematics, no ray construction) | partial gap |
| Feynman diagrams | inknertia v0.1.0 (weeks old) | contested |
| Bloch sphere | czbloch + tybloch (two fresh v0.1.0s) | contested |
| 3D molecules | molfig v0.1.2 (mesh-pipeline, very early) | contested |

**Demand calibration:** Universe publishes no download counts; GitHub stars are the
signal. ~100–150★ = successful science-niche package (quill, diagraph). plotsy-3d's
107★ for limited 3D surface plots demonstrates 3D demand specifically.

**Borrow, don't build:**
- **cetz 0.5.2** — all actual drawing (the only runtime dependency).
- **wyckoff engine** — `linalg`/`project`/`scene`/`render` already written, reviewed,
  and visually validated; the core is an extraction+generalization, not a rewrite.
- **seekpath** (Python, offline) — ground-truth fixtures for k-path validation.
- **pyxtal/pymatgen** (Python, offline) — already power wyckoff's data and fixtures.

## Features

### Wave 1 — 3D visualization (selected; ≈2 weeks agentic effort total)

| Feature | What it gives | Effort (rough) |
|---|---|---|
| **`scenery` core package** — typed 2D/3D primitives, orthographic camera, depth sort, styling/themes, CeTZ backend, axes/legend/colorbar | The unified abstraction every package builds on; Typst's first programmatic 3D API | ~4–5 days |
| **Monorepo infrastructure** — scaffold, shared test harness + Python fixture tooling, CI matrix, `TYPST_PACKAGE_PATH` dev flow, per-package publishing checklist, gallery README | Maintainability of the family | ~1–2 days |
| **`wyckoff` migration** — move in, refactor onto core (delete its private engine, ~40% of its code), ship 0.1.0 to Universe from here | First consumer; proves the extraction (gallery must be pixel-identical) | ~1–2 days |
| **`brillouin` package** — reciprocal lattice, Wigner-Seitz BZ polyhedron, Setyawan–Curtarolo k-points/paths, optional band-path panel | Second 3D consumer; proves the core is general; same audience as wyckoff | ~3–4 days |

### Deferred (parked in ONE tracking issue on the monorepo)

- **Wave 2 (2D-heavy):** `tensornet` (MPS/PEPS/einsum diagrams), `lattice` (spin models),
  `phase-portrait` (ODE flows), `polyhedra` (solids/tilings/nets), `ray-optics`
  (lens/mirror diagrams). All clean gaps; deferred to keep wave 1 focused on 3D.
- **WASM era:** `complex-viz` (domain coloring — needs per-pixel compute, violates the
  pure-Typst-now constraint); WASM projector/sorter for large scenes.
- **Core roadmap:** perspective camera, BSP-correct translucency sorting.

### Dropped (with reason)

- **feynman** — inknertia v0.1.0 exists; fails admission rule 1 (weakly). Revisit only if
  it stalls.
- **bloch, molecules-3D** — two fresh Bloch packages and molfig already compete; fails
  rule 1.

## Modules

Dependency DAG: `scenery ← wyckoff`, `scenery ← brillouin`; a thin optional adapter lets
`brillouin` accept a wyckoff structure (soft dependency, not required).

### Package: `scenery` (core)

| Module | Purpose | Depends on |
|---|---|---|
| `linalg` | vectors/matrices, cetz-free (lifted from wyckoff) | — |
| `camera` | view transforms; azimuth/elevation orthographic projection; 2D = identity mode | linalg |
| `scene` | typed primitives (sphere, segment, face, mesh, arrow, label, edge); `build-scene` → pure data (prims, bbox); `group(transform, ..)` flattening helper | linalg |
| `shape` | generators: convex hull, UV-sphere/cylinder/cone meshes, extrusions | linalg, scene |
| `style` | themes, palettes, stroke/fill/lighting defaults | — |
| `render` | painter's depth sort, CeTZ backend, canvas sizing, coverage-suppression heuristic | scene, camera, style, cetz |
| `annotate` | axes triad, legend, colorbar, projected labels | scene, render |

Public API (three levels, the pattern wyckoff proved): `build-scene` (pure data),
`render-scene` (Typst content), `scene-group` (raw CeTZ commands for canvas composition).

### Package: `wyckoff` (migrated)

Keeps `symmetry`, `lattice`, `structure`, `prototypes`, `data`; deletes `linalg`,
`project`, `scene`, `render`; imports `@preview/scenery`. Migration acceptance test:
the existing gallery renders pixel-identical before/after.

### Package: `brillouin`

| Module | Purpose | Depends on |
|---|---|---|
| `reciprocal` | reciprocal lattice vectors from direct lattice params (+ wyckoff-structure adapter) | scenery linalg |
| `wigner-seitz` | BZ as 3D Voronoi cell (half-space intersection, runtime, pure Typst) | scenery shape |
| `kpath` | Setyawan–Curtarolo high-symmetry points/paths per extended Bravais variant | — |
| `figure` | BZ polyhedron + labeled k-points/path arrows; optional 2D band-path panel | scenery |

### Shared infrastructure

`tools/` (one Python venv: generators + fixture emitters), per-package `tests/`
(assert-based Typst suites; compile = pass), one CI matrix (all package tests + all
example galleries compile), per-package `typst.toml`, root gallery README, publishing
checklist per package.

## Technical approaches

**D1 — Names.** Core package & repo: **`scenery`** (verified free on Universe
2026-07-11; alternatives `vantage`, `prism` also free; `diorama`, `maquette` taken).
Domain packages: `wyckoff` (ours), `brillouin` (verified free). The repo carries the
core's name, as the cetz repo does for its family.

**D2 — Cross-package dependencies.** Published Universe packages cannot path-import
outside their root but CAN depend on other `@preview` packages (cetz-plot → cetz is the
precedent). So domain packages import `@preview/scenery:0.1.0`; during development, the
Makefile and CI set `TYPST_PACKAGE_PATH` to the monorepo checkout so `@preview/scenery`
resolves locally. Rejected alternative: one giant package (kills per-package publishing
and the library story).

**D3 — Scene representation.** Flat typed-primitive list + bbox (wyckoff-proven), plus a
`group(transform, ..prims)` helper that flattens at build time. Rejected: retained scene
graph (heavier, YAGNI — painter's sort needs a flat list anyway); immediate-mode draw
calls (loses global depth sorting).

**D4 — Camera.** Orthographic azimuth/elevation only in wave 1, with the API shaped so a
perspective mode is purely additive (tracking issue). Rejected for now: perspective from
day one (complicates depth keys and sphere sizing for little wave-1 gain).

**D5 — Depth sorting.** Single-pass painter's algorithm on per-primitive depth keys;
documented limitation on intersecting translucent faces (wyckoff-proven, fine for static
unit-cell-scale figures). BSP splitting goes to the tracking issue.

**D6 — Shading.** Spheres = gradient-shaded circles with offset highlight + darker
outline (the Materials-Project look wyckoff ships). Generic meshes (BZ cells, future
surfaces) = flat-shaded faces from a single light direction + edge strokes. Rejected:
per-vertex smooth shading (not achievable in CeTZ fills at reasonable cost).

**D7 — Wigner-Seitz construction (brillouin).** Runtime bisector half-space
intersection: enumerate reciprocal-lattice neighbors within 2 shells (≤ ~50 planes);
intersect all plane triples (3×3 linear solves, ~20k of them); keep vertices inside
every half-space (tolerance-deduped); group vertices into faces by generating plane.
Pure Typst, bounded cost at figure scale. Rejected: offline precomputation — impossible,
BZ geometry varies continuously with lattice parameters, not just by Bravais class.

**D8 — k-paths (brillouin).** Encode the Setyawan–Curtarolo (2010) closed-form tables —
k-point coordinates as formulas in (a, b, c, α, β, γ) per extended Bravais variant —
directly in Typst, so any lattice parameters work at runtime. Validate against
seekpath-generated JSON fixtures offline (the wyckoff ground-truth pattern). Rejected:
shipping per-structure seekpath output (a library must handle continuously varying
parameters).

## Quality requirements

- **Performance:** ≤ ~10 s compile per figure at ~2,000 primitives; this documents the
  practical pure-Typst scene-size cap. Larger scenes are the WASM roadmap's job.
- **Compatibility:** Typst 0.14, cetz 0.5.2 (the wyckoff baseline); version floors
  recorded in every `typst.toml`.
- **Extensibility:** the scene data layer is plain arrays/dicts end-to-end, so a WASM
  projector/depth-sorter can replace the Typst implementation without any API change.
- **Testing:** every package follows wyckoff's discipline — assert-based Typst test
  suites (compile = pass), Python ground-truth fixtures for anything with an independent
  reference (seekpath for k-paths, pymatgen for structures), and CI that compiles every
  example gallery.

## Open questions / out of scope

- **Single tracking issue:** all deferred items (wave-2 packages, WASM era, perspective
  camera, BSP sorting) are recorded in one GitHub issue on this repo — not designed
  further until picked up.
- **wyckoff logistics:** the existing private repo `GiggleLiu/wyckoff` (PR #1 open, CI
  green) is absorbed here; after migration it is archived with a pointer. The Universe
  submission of `wyckoff:0.1.0` happens from this monorepo, after `scenery:0.1.0` is
  published (wyckoff's manifest will depend on it).
- **Out of scope for this design:** anything failing the three admission rules;
  competing with lilaq/cetz-plot on general plotting; CIF import (stays on wyckoff's own
  roadmap).
