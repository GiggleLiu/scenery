# Milestone design: file import + molecular rendering

**Date:** 2026-07-12
**Theme:** Point wyckoff at a real structure file and get a good-looking figure out.
**Tracking:** advances issue [#17](https://github.com/GiggleLiu/scenery/issues/17) (CIF import, perspective camera, BSP, WASM accelerator) and closes the `.xyz`/`.pdb` request in [#17's comment thread](https://github.com/GiggleLiu/scenery/issues/17).

This milestone deliberately does **not** add new feature-category packages (`tensornet`, `lattice`, `phase-portrait`, …). All work lands in the existing `scenery` core and `wyckoff` package.

## Objective

1. Import real-world structure files — `.xyz`, extended-xyz, `POSCAR`, `.cif`, `.pdb` — into wyckoff figures.
2. Render molecules (non-periodic structures) as first-class citizens.
3. Raise rendering quality and scale: perspective camera, better shading, correct translucent ordering (BSP), and protein-scale performance.

## Scope

**In scope**
- Rust WASM I/O + geometry engine (`wyckoff-io`): all five format parsers; projection, depth-sort, and BSP splitting for large/robust scenes.
- wyckoff **molecule mode**: a lattice-free structure path plus a `molecule()` wrapper and `molecule()`-aware figure entry.
- Molecule render modes: space-filling / CPK and licorice, plus split-color bonds. (Ball-and-stick already exists.)
- Perspective camera (additive to the scenery camera API).
- Shading polish on the existing gradient/flat-shade model.
- van der Waals radius data column (for CPK).

**Out of scope**
- New feature-category packages.
- Non-standard crystallographic settings (unchanged wyckoff limitation).
- Full CIF (arbitrary symmetry-operation loops) — a pragmatic subset only; see below.

## Architecture: the Rust/Typst boundary

The load-bearing decision is **where parsing and geometry cross from Rust into Typst**. The rule: **Rust does throughput-bound text and geometry; Typst keeps the validated crystallography and all rendering styling.**

```
file bytes ──► [Rust wyckoff-io.wasm] ──► normalized record ──► [Typst wyckoff] ──► [Typst scenery core] ──► CeTZ
                 parse xyz/extxyz/                (CBOR/JSON)      symmetry expansion    primitives, themes,
                 poscar/cif/pdb                                    molecule mode         gradient shading
                 projection + depth-sort                          bond detection
                 BSP split (translucent)                          render-mode selection
```

### Why this boundary

- **Parsers in Rust, not Typst.** Real parsers with real error handling beat `str.split` chains; this is what makes PDB-at-protein-scale and malformed-file handling robust. One crate, not split-brain parsing across two languages.
- **Symmetry expansion stays in Typst.** CIF returns a spacegroup number + asymmetric unit; wyckoff expands it through its **existing** pyxtal/pymatgen-cross-validated tables. We do not reimplement crystallography in Rust.
- **Projection/depth-sort/BSP in Rust, styling in Typst.** The Rust engine returns *ordered, split* primitives with depth keys; Typst still owns colors, gradients, opacity, themes. Rendering identity is unchanged; only the geometry pipeline is accelerated. The pure-Typst path in `render.typ` remains the default for small scenes and the fallback; the WASM engine is the robust/large path.

### Host-agnostic core (future JavaScript reuse)

The `wyckoff-io` crate is written **host-agnostic**: zero Typst/CeTZ assumptions, a stable serialized data contract (structure records in; primitives-with-depth out). All rendering — colors, gradients, themes, vector emission — stays on the Typst side, because a Typst plugin is pure bytes-in/bytes-out and *cannot* emit Typst content. This is a deliberate boundary, not an accident:

- **"Move most features to WASM" is not the goal, and isn't possible.** The painting layer is structurally Typst-side; only compute (parsing, projection, depth-sort, BSP, geometry) moves to Rust.
- **JS compatibility is not gated by WASM.** Typst already runs on the web (typst.app / typst.ts are WASM builds of the compiler), so a pure-Typst package already works in a browser. The *only* thing the Rust core buys for JavaScript is reuse **outside** Typst — a future standalone web viewer that loads the same `.wasm`, gets geometry back, and paints with its own Canvas/WebGL/SVG.
- **Keep the door open, don't walk through it now (YAGNI).** No JS renderer or JS bindings this milestone; just enforce the host-agnostic contract so the option stays free.

### Typst Universe compatibility

WASM plugins are a first-class Typst feature and Universe-publishable; adding Rust does **not** block registration. Constraints the crate must honor:
- Compiled to `wasm32-unknown-unknown` (freestanding, no WASI): no filesystem, network, threads, clock, or randomness — pure byte-in/byte-out functions. Parsing and geometry fit this exactly.
- Typst does `read(path)` and passes the bytes to the plugin; the plugin never touches disk. (This is already the chosen boundary.)
- The prebuilt `.wasm` is committed into the package and shipped in the Universe tarball, so end users need no Rust toolchain. Keep it lean (`opt-level="z"`, `lto`, `strip`, `wasm-opt`) to stay under Universe's package-size ceiling.
- Output must be deterministic (Universe/Typst require reproducibility).

### Normalized record (plugin → Typst)

A single schema all parsers target:
```
{
  lattice: none | (vec3, vec3, vec3),        // absent for molecules
  atoms:   [ { element, cart: vec3 } ],       // always Cartesian, Ångström
  spacegroup: none | int,                     // CIF only, triggers Typst expansion
  asym_unit:  none | [ { element, frac: vec3 } ],
  bonds:   none | [ (i, j) ],                 // PDB CONECT; else auto-detected in Typst
  meta:    { source_format, n_atoms, hetatm_flags?, chains? }
}
```

## Format handling

| Format | Periodic? | Parser home | Typst path | Notes |
| --- | --- | --- | --- | --- |
| `.xyz` | no | Rust | molecule mode | simplest; proves the pipeline (Stage 1) |
| extended-xyz | yes (Lattice=) | Rust | crystal (lattice+basis) | reuses existing basis path |
| `POSCAR` | yes | Rust | crystal (lattice+basis) | direct/cartesian coordinate flag |
| `.cif` | yes | Rust | crystal via symmetry expansion | **subset:** `atom_site` loop + a single `_space_group_IT_number`; explicit-symmetry-op loops rejected with a clear error |
| `.pdb` | no | Rust | molecule mode | ATOM/HETATM, CONECT bonds, chains; protein-scale via the accelerator |

CIF subset boundary is explicit: if a CIF carries symmetry-operation loops we can't map to a spacegroup number, the parser errors with a message pointing to the explicit-atoms path — never silently mis-expands.

## wyckoff-side changes

- **Molecule mode:** `structure(atoms: (...))` with no `lattice` becomes valid (currently the explicit mode requires lattice vectors). A new `molecule()` wrapper renders it with no cell grid and no a/b/c triad — just atoms, bonds, optional labels/legend, and (for molecules) an optional orientation gnomon rather than a crystallographic axes triad.
- **Import entry points:** `import-xyz(path)`, `import-poscar(path)`, `import-cif(path)`, `import-pdb(path)` (and extended-xyz auto-detected within `import-xyz`). Each reads the file, calls the plugin, and returns a `structure`/`molecule` consumable by `crystal()`/`molecule()`.
- **Bond detection:** molecules default to the existing distance rule (1.15× covalent-radius sum, 0.4 Å floor); PDB CONECT records, when present, override it.

## Visualization changes (pure Typst)

- **Render modes** (new `mode:` option on `crystal()`/`molecule()`):
  - `ball-and-stick` (default, existing behavior)
  - `space-filling` / `cpk` — spheres at van der Waals radius, no bonds
  - `licorice` — uniform thin bonds + small caps
  - split-color bonds — each half colored by its atom (applies to ball-and-stick/licorice)
- **Perspective camera:** `camera(..., mode: "perspective", focal: …)`. Additive dispatch in `project()` (a divide-by-depth); orthographic path untouched.
- **Shading polish:** specular highlight stop and optional outline on `_sphere-gradient`; bond cylinders. Works on `render.typ`'s existing model.

## Data changes

- Add a **van der Waals radius** column to `wyckoff/data/elements.json`, regenerated via the existing `make data` step (source: standard vdW radii tables; falls back to `r-atom` where missing). Required for CPK; no other column changes.

## Staging (each stage independently shippable)

1. **Foundation** — Rust `wyckoff-io` crate scaffold, `wasm32` build wired into the Makefile + CI, plugin ships in `wyckoff/`. End-to-end `.xyz` parse → molecule mode → figure. Proves the whole pipeline on the simplest format.
2. **Periodic formats** — extended-xyz, POSCAR, CIF-subset. Reuse crystal lattice+basis and Typst symmetry expansion.
3. **Molecule mode + visualization** — `molecule()` path, CPK/licorice/split-bonds, perspective camera, shading polish. Includes the gallery rebaseline.
4. **Protein flagship** — PDB parser + Rust projection/depth-sort accelerator + BSP splitting for translucent faces. Renders real proteins; fixes intersecting-translucent-polyhedra ordering.

## Testing & gates

- **Parser fixtures:** golden input files (`.xyz`/extxyz/POSCAR/`.cif`/`.pdb`) with expected normalized-record JSON, cross-validated against ASE/pymatgen where applicable, in the Rust crate's test suite.
- **Rust unit tests** for projection/depth-sort/BSP against small analytic scenes.
- **Typst regression:** existing wyckoff/scenery compile tests stay green for the pure-Typst path.
- **Pixel-identical gallery gate — rebaseline required.** Shading polish and any WASM-path rendering change repaints figures; Stage 3 regenerates and reviews new baselines rather than asserting byte-identity to old ones. This is the milestone's main gate cost and is called out so it isn't mistaken for a regression.
- **Accelerator equivalence:** for scenes small enough for both paths, the WASM engine and the pure-Typst engine must produce the same primitive ordering (modulo documented BSP splits).

## Risks

- **Toolchain commitment:** introduces a Rust `wasm32` build + CI cross-compile — a permanent change to contributor onboarding and the "pure Typst" story. Mitigated by shipping the prebuilt `.wasm` in the package so *end users* need no Rust; only maintainers regenerating the plugin do.
- **CIF surface area:** the format is vast. The subset boundary keeps this tractable but will reject some real-world CIFs — the error message must guide users to the explicit path.
- **PDB heterogeneity:** alternate locations, insertion codes, multi-model files. Parse the common case robustly; reject/warn on the rest rather than mis-render.
- **Gallery churn:** rebaselining is intentional but must be reviewed image-by-image so shading changes don't mask a real regression.
