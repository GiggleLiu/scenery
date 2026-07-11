# wyckoff — Crystal Structure Visualization for Typst

**Date:** 2026-07-11
**Status:** Approved design, pre-implementation
**Target:** Typst Universe package `wyckoff:0.1.0`

## Goal

A pure-Typst package that renders Materials Project–quality crystal structure
figures directly in Typst documents. Symmetry-native: structures are specified
the way crystallographers (and generative models like
[CrystalFormer](https://github.com/deepmodeling/CrystalFormer)) describe them —
space group + Wyckoff positions + free parameters + lattice parameters — and the
package expands symmetry itself. Supports the 230 3D space groups and the 80 2D
layer groups. No package on Typst Universe covers this niche (verified against
the full package index, 2026-07-11).

## Non-goals (v0.1.0)

- CIF import (CrystalFormer's native output is not CIF; deferred to a later release)
- Brillouin zones, Wigner-Seitz cells, Miller-plane rendering
- Non-standard space-group settings (v1 ships standard ITA settings, conventional cells)
- Perspective projection, ray-traced quality, animation

## Architecture (Approach C: pure Typst, plugin-ready)

Pipeline: **symmetry expansion → geometry → scene → orthographic projection →
painter's depth sort → CeTZ draw**.

All runtime code is Typst script. Symmetry tables are pre-generated offline
(Python + spglib/pymatgen) into JSON data files shipped in the package. The
engine/renderer boundary is a hard interface so a WASM engine could replace the
Typst engine in a future release without API changes.

### Public API

```typst
#import "@preview/wyckoff:0.1.0": structure, crystal, crystal-group, prototypes

// Space group + Wyckoff sites (CrystalFormer-native)
#let nacl = structure(
  spacegroup: 225,
  lattice: (a: 5.64),               // Å; only the crystal system's free params
  sites: (
    (element: "Na", wyckoff: "a"),
    (element: "Cl", wyckoff: "b"),
  ),
)

// Layer group ⇒ 2D slab (periodic in a,b; finite thickness)
#let mos2 = structure(
  layergroup: 72,
  lattice: (a: 3.16),
  sites: (
    (element: "Mo", wyckoff: "a"),
    (element: "S",  wyckoff: "h", z: 1.56),  // free params per site
  ),
)

// Escape hatch: explicit lattice vectors + full basis (P1)
#let srtio3 = structure(
  lattice: ((3.9, 0, 0), (0, 3.9, 0), (0, 0, 3.9)),
  atoms: (("Sr", (0.5, 0.5, 0.5)), ("Ti", (0, 0, 0)), ("O", (0.5, 0, 0)),
          ("O", (0, 0.5, 0)), ("O", (0, 0, 0.5))),
)

// Prototype library one-liners
#let si = prototypes.diamond("Si", a: 5.43)

#crystal(
  nacl,
  view: (azimuth: 30deg, elevation: 12deg),
  supercell: (2, 2, 2),
  bonds: auto,             // covalent-radii heuristic, or explicit rules:
                           // ((elements: ("Ti", "O"), max: 2.2),)
  polyhedra: ("Ti",),      // coordination polyhedra around these elements
  labels: false,           // element/site labels on atoms
  legend: true,
  axes: true,              // a,b,c arrow triad in corner
  radius: 0.4,             // sphere display size, fraction of atomic radius
  width: 8cm,
)
```

- `crystal()` returns Typst content.
- `crystal-group()` emits the same scene as CeTZ draw commands for use inside an
  existing `cetz.canvas`, so users can annotate figures (arrows, labels, planes).
- `structure()` validates on construction: lattice params must match the group's
  crystal system (only free ones accepted), Wyckoff letters must exist in the
  group, per-site free coordinates must match the site's degrees of freedom.
- Units of free Wyckoff coordinates: fractional for space groups (all three
  directions periodic). For layer groups, in-plane free coordinates (x, y) are
  fractional; the out-of-plane coordinate z is in Å (no c period exists).
  The returned value carries the fully expanded atom list — the renderer never
  touches symmetry.
- Prototype library (v1 set): sc, fcc, bcc, hcp, diamond, rocksalt, cesium-chloride,
  zincblende, wurtzite, fluorite, rutile, perovskite, graphene, hexagonal-BN,
  2H-TMD (e.g. MoS₂).

### Data files (committed, built by `tools/` Python scripts)

- `data/spacegroups.json` — per group (230, standard ITA setting, conventional
  cell): crystal system, general-position ops as 3×4 affine matrices, Wyckoff
  positions as (letter, multiplicity, site-representative affine expression,
  free-coordinate mask).
- `data/layergroups.json` — same schema for the 80 layer groups (periodic in a,b).
- `data/elements.json` — per element: Jmol/CPK color, covalent radius (bonding),
  atomic radius (display).

Source: pymatgen/spglib for space groups. **Risk (flagged):** layer-group tables
are not in pymatgen; generator derives them via the published layer-group ↔
space-group correspondence (each layer group's operations are a space group's
with c-translations removed; ITA Vol. E / Bilbao Crystallographic Server list the
mapping). Fallback: hand-encode from Bilbao — tedious but bounded (80 groups).

### Engine (`src/engine/`, pure functions, plugin-ready boundary)

```
expand(structure) -> (atoms: ((element, frac-pos, site-index), ..), lattice-vectors)
```

- Apply every group op to each site representative; wrap into [0,1); dedup
  within tolerance; **assert orbit size == Wyckoff multiplicity** (catches bad
  data and users placing a free coordinate on a more special position).
- Downstream geometry (same data-in/data-out style): boundary-image atoms
  (copies at fractional 0↔1 along periodic directions), supercell replication,
  O(N²) bond search (covalent radii × tolerance, or user rules), coordination
  polyhedra as convex hulls of bonded neighbors (≤12 vertices; brute-force hull).
- Everything after `expand` speaks Cartesian coordinates and plain arrays.

### Renderer (`src/render/`, CeTZ)

Orthographic projection, azimuth/elevation view. One primitive list — spheres,
half-bonds, polyhedron faces, cell edges — depth-sorted (painter's algorithm),
drawn back-to-front:

- **Spheres:** circles with radial gradient offset toward the light + darker
  outline (shaded-ball look).
- **Bonds:** split at midpoint; each half colored by its endpoint element
  (MP two-tone style) and depth-keyed independently.
- **Polyhedra:** translucent fills with visible edges; back-face culling;
  centroid depth keys.
- **Cell edges:** thin neutral lines, depth-sorted with everything else.
- **Labels** drawn last at projected positions; **legend** as swatch rows;
  **axes triad** in a corner.

Accepted limitation: painter's algorithm can mis-sort intersecting translucent
polyhedra. Fine for static figures at unit-cell scale.

Performance envelope: target scenes are 10–300 rendered atoms; O(N²) bond search
at that scale is tens of ms in Typst script. Large supercells of complex cells
may be slow — documented, and the motivation for the plugin-ready boundary.

## Testing

1. **Engine vs. pymatgen ground truth.** Python generator (via the
   `gen-reference-test-data` skill) emits JSON fixtures: ~30 representative
   structures spanning all 7 crystal systems + layer-group cases (NaCl, diamond,
   wurtzite, perovskite, rutile, graphene, 2H-MoS₂, …) with pymatgen-expanded
   atom lists. Typst tests assert `expand()` matches within tolerance.
2. **Universal multiplicity check.** For all 230+80 groups, every Wyckoff
   position with random free parameters must expand to exactly its multiplicity.
3. **Visual regression.** Example gallery compiled in CI; golden PNGs reviewed
   on change (same pattern as cetz's test setup).

## Repo & publishing

- Repo `GiggleLiu/wyckoff`, MIT, structured like `ptable-amat`: `typst.toml`,
  `src/`, `data/`, `tools/`, `tests/`, `examples/`, `Makefile`, CI (tests +
  gallery compile).
- README leads with a gallery grid: perovskite with TiO₆ octahedra, NaCl,
  diamond, MoS₂ slab; roadmaps CIF import and Brillouin zones.
- Publish `wyckoff:0.1.0` via the existing `typst/packages` fork flow.
- Name availability verified against the Universe index on 2026-07-11.

## Dependencies

- Runtime: `cetz` (drawing). Nothing else.
- Dev/offline: Python 3 + pymatgen + spglib (data generation, test fixtures).
