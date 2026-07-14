# Milestone design: file import + molecular rendering

**Date:** 2026-07-12
**Theme:** Point wyckoff at a real structure file and get a good-looking figure out.
**Tracking:** advances issue [#17](https://github.com/GiggleLiu/scenery/issues/17) (CIF import, perspective camera, BSP, WASM accelerator) and closes the `.xyz` half of the import request in [#17's comment thread](https://github.com/GiggleLiu/scenery/issues/17). The molecular-orbital formats (`.molden`, `.cube`, …) stay parked in #17; the normalized record below is designed so they slot in later without a schema change.

This milestone deliberately does **not** add new feature-category packages (`tensornet`, `lattice`, `phase-portrait`, …). All work lands in the existing `scenery` core and `wyckoff` package.

## Objective

1. Import real-world structure files — `.xyz`, extended-xyz, `POSCAR`, `.cif` — into wyckoff figures.
2. Render non-periodic molecular structures as first-class citizens.
3. Raise rendering quality and scale: perspective camera, better shading, correct translucent ordering (BSP), and large-scene performance.

## Scope

**In scope**
- Rust WASM crates, one workspace, **two artifacts** matching the package layering:
  - `wyckoff-io` (ships in `wyckoff/`): all four format parsers, CIF symmetry-op application, and auto bond detection (spatial-hash neighbor search).
  - `scenery-engine` (ships in `scenery/`): projection, depth-sort, and BSP splitting for large/robust scenes — a core capability reusable by `brillouin` and future 3D packages, per #17's core roadmap.
- wyckoff **molecule mode**: a lattice-free structure path plus a `molecule()` wrapper and `molecule()`-aware figure entry.
- Molecule render modes: space-filling / CPK and licorice. (Ball-and-stick and split-color bonds already exist — `figure.typ` draws every bond as two atom-colored halves; new here is only an optional single-color bond style.)
- Perspective camera (additive to the scenery camera API).
- Shading polish on the existing gradient/flat-shade model.
- van der Waals radius data column (for CPK).

**Out of scope**
- New feature-category packages.
- Non-standard crystallographic settings (unchanged wyckoff limitation).
- Full CIF (occupancy/disorder, multi-block files, exotic tags) — a pragmatic subset only; see below. Symmetry-op loops ARE supported (applied directly in Rust).

## Architecture: the Rust/Typst boundary

The load-bearing decision is **where parsing and geometry cross from Rust into Typst**. The rule: **Rust does throughput-bound text and geometry; Typst keeps the validated crystallography and all rendering styling.**

```
file bytes ──► [Rust wyckoff-io.wasm] ──► normalized record ──► [Typst wyckoff] ──► [Typst scenery core] ──► CeTZ
                 parse xyz/extxyz/                (JSON)           symmetry expansion    primitives, themes,
                 poscar/cif                                        (spacegroup tables)   gradient shading
                 CIF symmetry-op apply                             molecule mode
                 auto bond detection                               bond-rule overrides
                                                                   render-mode selection

               [Rust scenery-engine.wasm]  ◄── primitives ── [Typst scenery core]
                 projection + depth-sort       (large scenes)
                 BSP split (translucent)
```

### Why this boundary

- **Parsers in Rust, not Typst.** Real parsers with real error handling beat `str.split` chains; this is what makes large-scene handling and clear error messages on invalid input robust. One crate, not split-brain parsing across two languages.
- **Table-based symmetry expansion stays in Typst.** When a CIF carries only a spacegroup identifier (IT number or H-M symbol), the parser returns it + the asymmetric unit, and wyckoff expands through its **existing** pyxtal/pymatgen-cross-validated tables. We do not reimplement table crystallography in Rust.
- **But explicit symmetry-op loops are applied in Rust.** When a CIF states its own `_symmetry_equiv_pos_as_xyz` loop (as most database-exported CIFs do), the parser applies those literal affine ops and returns explicit atoms. This is ~20 lines of arithmetic on operations the file itself asserts — not table crystallography — and it sidesteps the non-standard-settings limitation for imported files, because the file is self-describing.
- **Auto bond detection in Rust (Stage 4, not Stage 2).** The distance rule over all atom pairs is O(N²) and, for large imported scenes, dominates compile time long before depth-sorting does — so it moves to Rust *where that scale actually bites*: alongside `scenery-engine` in Stage 4. A spatial-hash neighbor search (covalent radii compiled into the crate, same 1.15×/0.4 Å rule) fills the record's `bonds` field. Through Stage 3, imports use the existing Typst `find-bonds` in `geometry.typ`, which is correct and fast for unit-cell-scale structures; it also remains the path for hand-built structures and custom bond rules, which override imported bonds. (Resequenced from Stage 2: at unit-cell scale the Typst loop is not the bottleneck, and deferring avoids coupling the Rust build to the Python radii-codegen before there's a payoff.)
- **Projection/depth-sort/BSP in Rust (`scenery-engine`), styling in Typst.** The engine returns *ordered, split* primitives with depth keys; Typst still owns colors, gradients, opacity, themes. Rendering identity is unchanged; only the geometry pipeline is accelerated. The pure-Typst path in `render.typ` remains the default for small scenes and the fallback; the WASM engine is the robust/large path. This crate ships in `scenery/`, not `wyckoff/`: depth-sorting is a core concern (#17 lists the "WASM projector/depth-sorter drop-in" under the core roadmap) and must be reachable by `brillouin` and future 3D packages.

### Host-agnostic core (future JavaScript reuse)

Both crates are written **host-agnostic**: zero Typst/CeTZ assumptions, a stable serialized data contract (`wyckoff-io`: file bytes in, structure record out; `scenery-engine`: primitives in, primitives-with-depth out). All rendering — colors, gradients, themes, vector emission — stays on the Typst side, because a Typst plugin is pure bytes-in/bytes-out and *cannot* emit Typst content. This is a deliberate boundary, not an accident:

- **"Move most features to WASM" is not the goal, and isn't possible.** The painting layer is structurally Typst-side; only compute (parsing, projection, depth-sort, BSP, geometry) moves to Rust.
- **JS compatibility is not gated by WASM.** Typst already runs on the web (typst.app / typst.ts are WASM builds of the compiler), so a pure-Typst package already works in a browser. The *only* thing the Rust core buys for JavaScript is reuse **outside** Typst — a future standalone web viewer that loads the same `.wasm`, gets geometry back, and paints with its own Canvas/WebGL/SVG.
- **Keep the door open, don't walk through it now (YAGNI).** No JS renderer or JS bindings this milestone; just enforce the host-agnostic contract so the option stays free.

### Typst Universe compatibility

WASM plugins are a first-class Typst feature and Universe-publishable; adding Rust does **not** block registration. Constraints the crate must honor:
- Compiled to `wasm32-unknown-unknown` (freestanding, no WASI): no filesystem, network, threads, clock, or randomness — pure byte-in/byte-out functions. Parsing and geometry fit this exactly.
- Typst does `read(path)` and passes the bytes to the plugin; the plugin never touches disk. (This is already the chosen boundary.)
- The prebuilt `.wasm` blobs are committed into their packages and shipped in the Universe tarballs, so end users need no Rust toolchain. Keep them lean (`opt-level="z"`, `lto`, `strip`, `wasm-opt`) to stay under Universe's package-size ceiling — two artifacts means the budget is watched per package.
- Output must be deterministic (Universe/Typst require reproducibility).
- **Reproducible builds as a review gate:** pin the toolchain (`rust-toolchain.toml`) and have CI rebuild each `.wasm` from source and diff it against the committed blob. A binary a reviewer can't regenerate is a binary a reviewer can't trust; this turns provenance into a checkable gate and enforces the determinism Universe wants.

### Normalized record (plugin → Typst)

A single schema all parsers target. The `wyckoff-io` parser record is serialized as **JSON** (Typst decodes with `json.decode`): the record is small (hundreds of atoms), so JSON's readability makes golden-file fixtures directly reviewable and keeps the debugging surface plain. CBOR is reserved for the `scenery-engine` primitive stream (Stage 4), where arrays are large and size/decode speed dominate.
```
{
  lattice: none | (vec3, vec3, vec3),        // absent for molecules
  atoms:   [ { element, cart: vec3 } ],       // always Cartesian, Ångström
  spacegroup: none | int,                     // CIF without op loop: triggers Typst table expansion
  asym_unit:  none | [ { element, frac: vec3 } ],
  bonds:   none | [ (i, j) ],                 // from the file when explicit, else Rust auto-detection
  meta:    { source_format, n_atoms }
}
```
For CIFs carrying an explicit symmetry-op loop, the ops are applied in Rust and the record comes back as explicit `atoms` with `spacegroup: none` — the identifier path is only for CIFs that state a spacegroup without ops.

## Format handling

| Format | Periodic? | Parser home | Typst path | Notes |
| --- | --- | --- | --- | --- |
| `.xyz` | no | Rust | molecule mode | simplest; proves the pipeline (Stage 1) |
| extended-xyz | yes (Lattice=) | Rust | crystal (lattice+basis) | reuses existing basis path |
| `POSCAR` | yes | Rust | crystal (lattice+basis) | direct/cartesian coordinate flag |
| `.cif` | yes | Rust | crystal (two sub-paths, see below) | **subset:** `atom_site` loop + symmetry via op-loop application or spacegroup lookup; exotic features (disorder/occupancy, multi-block, symmetry-less files) rejected with a clear error |

CIF symmetry handling, in priority order:
1. **Explicit op loop** (`_symmetry_equiv_pos_as_xyz` / `_space_group_symop_operation_xyz`) — applied directly in Rust, atoms returned explicit. This is the path most database exports (COD, ICSD, Materials Project) take, including trivial P1 files.
2. **Spacegroup identifier only** (`_space_group_IT_number` or `_symmetry_space_group_name_H-M` mapped to a number) — asymmetric unit returned, wyckoff's Typst tables expand it.
3. **Neither** — rejected with an error naming the missing tags; never silently mis-expands.

## wyckoff-side changes

- **Molecule mode:** `structure(atoms: (...))` with no `lattice` becomes valid (currently the explicit mode requires lattice vectors). A new `molecule()` wrapper renders it with no cell grid and no a/b/c triad — just atoms, bonds, optional labels/legend, and (for molecules) an optional orientation gnomon rather than a crystallographic axes triad.
- **Import entry points:** `import-xyz(path)`, `import-poscar(path)`, `import-cif(path)` (and extended-xyz auto-detected within `import-xyz`). Each reads the file, calls the plugin, and returns a `structure`/`molecule` consumable by `crystal()`/`molecule()`.
- **Bond detection:** imported structures arrive with `bonds` already filled (from the file when explicit, else Rust's spatial-hash auto-detection with the same 1.15× covalent-radius-sum / 0.4 Å-floor rule). A user-supplied `bonds:` rules array on `crystal()`/`molecule()` overrides imported bonds and routes through the existing Typst `find-bonds`; hand-built structures keep the pure-Typst path unchanged.
  - **Supercell caveat:** imported `bonds` index unit-cell atoms, but `crystal(supercell: ...)` bonds the *displayed* atom set, which only exists at render time. So precomputed bonds are authoritative for molecules and for `supercell: (1, 1, 1)`; supercell rendering keeps the render-time Typst `find-bonds` (existing behavior) until `scenery-engine` gives that loop a fast home in Stage 4.

## Visualization changes (pure Typst)

- **Render modes** (new `mode:` option on `crystal()`/`molecule()`):
  - `ball-and-stick` (default, existing behavior — already draws split-color two-tone bonds)
  - `space-filling` / `cpk` — spheres at van der Waals radius, no bonds
  - `licorice` — uniform thin bonds + small caps, split-colored like ball-and-stick
  - optional single-color bond style (opt out of the existing two-tone split)
- **Perspective camera:** `camera(..., mode: "perspective", focal: …)`. Additive dispatch in `project()`; orthographic path untouched. The divide-by-depth is the easy part — the explicit work item is **auditing every consumer of `project()` that mixes world radii with screen units**, which are all orthographic assumptions: wyckoff's screen bbox (`sx ± r` in `figure.typ`), the whole `occlude()` disk/slack heuristic, and `render.typ`'s depth-interval logic that feeds `r` into depth comparisons. Under perspective a sphere's screen radius depends on its depth; each of these needs a per-primitive projected radius.
- **Shading polish:** specular highlight stop and optional outline on `_sphere-gradient`; bond cylinders. Works on `render.typ`'s existing model.

## Data changes

- Add a **van der Waals radius** column to `wyckoff/data/elements.json`, regenerated via the existing `make data` step (source: Alvarez 2013 vdW table, which covers every element through ~96). Where genuinely missing, fall back to `1.5 × r-atom` — raw `r-atom` is roughly half a vdW radius and would render fallback atoms visibly shrunken in CPK mode. Required for CPK; no other column changes.
- **Covalent radii compiled into `wyckoff-io`** (generated from the same source as `elements.json`'s `r-cov`, via `make data`, so the Rust and Typst bond rules can never drift).

## Staging (each stage independently shippable)

1. **Foundation** — Rust workspace scaffold with the `wyckoff-io` crate, `wasm32` build wired into the Makefile + CI (including the rebuild-and-diff reproducibility gate), plugin ships in `wyckoff/`. End-to-end `.xyz` parse → **minimal molecule mode** → figure: the lattice-free structure path and a bare `molecule()` (default ball-and-stick, no furniture) land here because the demo needs them; render modes and polish wait for Stage 3. Proves the whole pipeline on the simplest format.
2. **Periodic formats** — POSCAR and CIF (op-loop application + spacegroup-identifier sub-paths); extended-xyz already shipped in Stage 1. Both reuse the existing explicit-periodic `structure(lattice:, atoms:)` path; the CIF identifier sub-path additionally reuses wyckoff's `group.ops` symmetry tables via a general-position expansion helper. Bond detection stays in Typst here (see Stage 4).
3. **Visualization** — full `molecule()` (gnomon, legend/labels), CPK/licorice, single-color-bond option, perspective camera (including the orthographic-assumption audit), shading polish. Includes the gallery rebaseline.
4. **Scale & translucent correctness** — `scenery-engine` crate: projection/depth-sort accelerator + BSP splitting for translucent faces, shipped in `scenery/`; plus Rust auto bond detection (spatial hash) with the Typst-equivalence gate. Renders large crystal supercells; fixes intersecting-translucent-polyhedra ordering.

## Testing & gates

- **Parser fixtures:** golden input files (`.xyz`/extxyz/POSCAR/`.cif`) with expected normalized-record JSON, cross-validated against ASE/pymatgen where applicable, in the Rust crate's test suite.
- **Rust unit tests** for projection/depth-sort/BSP against small analytic scenes.
- **Typst regression:** existing wyckoff/scenery compile tests stay green for the pure-Typst path.
- **Pixel-identical gallery gate — rebaseline required.** Shading polish and any WASM-path rendering change repaints figures; Stage 3 regenerates and reviews new baselines rather than asserting byte-identity to old ones. This is the milestone's main gate cost and is called out so it isn't mistaken for a regression.
- **Accelerator equivalence — pixel-level, not ordering-level.** "Same primitive ordering" is not well-defined across the two paths: the Typst renderer does fragment cutting (segments split into visible depth intervals), and the BSP path splits differently, so the two engines legitimately produce different primitive *sets*. The gate is instead: for scenes small enough for both paths, rendered output must be pixel-identical; ordering equivalence is asserted only on scenes where neither path splits anything.
- **Bond-detection equivalence:** Rust auto-detection and Typst `find-bonds` must return the same bond set on shared fixtures (both implement the same rule from the same radii source).

## Risks

- **Toolchain commitment:** introduces a Rust `wasm32` build + CI cross-compile — a permanent change to contributor onboarding and the "pure Typst" story. Mitigated by shipping the prebuilt `.wasm` in the package so *end users* need no Rust; only maintainers regenerating the plugin do.
- **CIF surface area:** the format is vast. Op-loop application covers the bulk of database exports, but occupancy/disorder, multi-block files, and exotic tags are still rejected — the error message must name the unsupported feature precisely so users know it's the file, not the tool.
- **Two-engine drift:** the Typst and Rust bond/geometry paths implement the same rules twice. The shared-source data generation and the equivalence gates above are the mitigation; any rule change must touch both sides in the same PR.
- **Gallery churn:** rebaselining is intentional but must be reviewed image-by-image so shading changes don't mask a real regression.
