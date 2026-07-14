# M4 Stage 4 (Scale & Translucent Correctness) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The milestone's hardest stage. Four deliverables: (#32) a new host-agnostic `scenery-engine` Rust crate — primitives + camera in over CBOR, depth-ordered (and split) primitives with depth keys out — mirroring `render.typ`'s pure pipeline bit-for-bit, with an opt-in `engine: "wasm"` path in scenery and wyckoff (pure Typst stays default AND fallback); (#33) BSP splitting of intersecting translucent faces inside the engine, applied only where faces actually intersect; the resequenced-from-Stage-2 Rust auto bond detection in `wyckoff-io` (spatial hash, covalent radii code-generated from the same source as `elements.json` so the two rules can never drift), filling the record's `bonds` and exposed as a render-time `detect_bonds` accelerator; and a ~1000-atom benchmark fixture demonstrating the accelerator compiles where pure Typst is impractically slow.

**Architecture:** One cargo workspace at the repo root, two crates, two committed artifacts: `wyckoff-io` (existing, ships `wyckoff/plugin/wyckoff_io.wasm`, all-JSON boundary) gains bond detection; `scenery-engine` (new, ships `scenery/plugin/scenery_engine.wasm`, all-CBOR boundary — the primitive stream is large, so size/decode speed dominate; verified: Typst 0.14.2 supports `cbor.encode(value)` and `cbor(bytes)`). The engine is host-agnostic: zero Typst/CeTZ assumptions; ALL color/gradient/opacity/theme stays Typst-side (a Typst plugin is bytes-in/bytes-out and cannot emit content). The Typst side resolves the two style-derived *geometric* facts the pipeline needs (per-face `opaque`, per-seg `w`) before serializing, runs `_prepare-faces` (mesh explosion + culling — needs the theme), and reassembles engine output records back onto the original styled primitives by index. Engine pipeline order: **cull → line-clip → BSP → depth keys → stable sort**, mirroring `render.typ:424–507` plus wyckoff's `occlude` (`figure.typ:213–244`) expression-for-expression, so that on scenes where BSP does not fire the two paths produce bit-identical fragments, depths, and pixels.

**Tech Stack:** Rust 1.93.1 (pinned by `rust-toolchain.toml`) + `wasm-minimal-protocol` + `serde` + `ciborium` (CBOR; wasm32-clean) + `serde_json` (wyckoff-io only); Typst 0.14.2 (`plugin()`, `cbor`/`cbor.encode`, `json`/`json.encode`, `sys.inputs`); cetz 0.5.2; GNU Make; GitHub Actions; Python tools venv (radii codegen + benchmark fixture).

Implements issues #32 (projection + depth-sort accelerator) and #33 (BSP splitting), plus the design doc's resequenced Rust bond detection. Design: `docs/plans/2026-07-12-file-import-molecular-rendering-design.md` (see "Architecture: the Rust/Typst boundary", "Host-agnostic core", "Typst Universe compatibility", "Testing & gates"). Note: issues #32/#33 were titled "wyckoff-io:" before the two-artifact decision; the design doc's `scenery-engine`-in-`scenery/` layout is authoritative.

## Global Constraints

- **Pure Typst stays the default and the fallback.** Every new `engine:` parameter defaults to `"typst"`; the default path evaluates *exactly* the same expressions as today (no refactor of `sort-prims`/`_clip-lines`/`occlude` semantics). Enforced at three levels per task: untouched pre-existing tests keep passing; new exact-equality asserts (`engine: "typst"` output == pre-Stage-4 output); and zero-diff PNG regeneration (`make -C <pkg> images` + `git status --short <pkg>/images` shows nothing) at the end of every task that does not intentionally add a new image.
- **The equivalence gate is layered, NOT naive ordering** (design doc, "Accelerator equivalence"):
  - **(a) Ordering equality** where NEITHER path splits anything: `engine-sort(...)` output must be **exactly equal** (Typst `assert.eq` on the full primitive dicts, including `depth`) to the pure path's output. Asserted programmatically in Typst tests.
  - **(b) Pixel identity** for scenes small enough for both paths, *including* scenes where both paths fragment-cut lines identically: the same `.typ` fixture compiled twice (`--input engine=typst` / `--input engine=wasm`) must produce **byte-identical PNGs** (`cmp`). This works because the engine renders through the *same* Typst styling/draw code (`_record` + the `scene-group` loop) on identically-valued geometry — the engine only replaces the pure-geometry stage.
  - **(c) BSP-only differences are documented, not byte-asserted:** scenes where translucent faces genuinely intersect produce a different (correctly split) primitive set by design; they are validated by Rust unit tests (fragment counts, plane-side invariants, hand-computed depth keys) plus a reviewed before/after example image — never by pixel-diff against the pure path.
- **Bit-identical mirroring is the fidelity rule for the engine.** Every mirrored function is transcribed **expression-for-expression, in the same evaluation order**, from its cited Typst source. Specifically: (1) the camera's trig is computed ONCE in Typst (`calc.cos`/`calc.sin`) and shipped to the engine as four float coefficients — the engine performs **only `+ - * /`, `sqrt`, comparisons, and `min`/`max`** (all IEEE-754 exactly-rounded and platform-deterministic; `sin`/`cos` are libm-dependent and must never be called in the engine); (2) Typst `vdot` sums left-to-right (`linalg.typ:26`) — Rust accumulates in the same order; (3) Typst's `.sorted(key:)` is stable — Rust uses stable `sort_by(f64::total_cmp)`; (4) no FMA, no `mul_add`. If any equality gate fails by last-ulp float divergence, **STOP and report for adjudication** (the documented fallback is a `1e-12`-tolerance ordering gate plus pixel gates restricted to non-cutting scenes — do not silently adopt it).
- **Engine determinism (Universe requires reproducible output):** no clock, filesystem, network, randomness, or threads (wasm32-unknown-unknown enforces most of this); never iterate a `HashMap`/`HashSet` (index lookups only — deterministic orders come from input order or explicit sorts); all tie-breaks specified in this plan (stable sort over the deterministic emission order: culled-survivor input order, line fragments at their parent's position in ascending-interval order, BSP fragments at their parent's position in negative-side-first split order).
- **Serialization rule:** every number crossing the CBOR boundary is mapped through Typst `float(..)` before `cbor.encode`, so the engine deserializes unambiguous CBOR doubles (no int/float coercion questions). `scenery-engine` speaks CBOR only; `wyckoff-io` stays all-JSON (its record is small and human-reviewable; new `detect_bonds` keeps the crate's existing JSON convention).
- **Two committed blobs, rebuilt only on purpose:** `wyckoff/plugin/wyckoff_io.wasm` is rebuilt + recommitted ONLY in Task 6 (bond detection changes that crate); `scenery/plugin/scenery_engine.wasm` is rebuilt + recommitted in every task that touches `scenery-engine/src` (Tasks 1–5). Build via `make -C <pkg> plugin` (runs `wasm-opt -Oz` when available — note whether it ran in the commit message the first time). Keep `scenery_engine.wasm` under ~300 KB (`wyckoff_io.wasm` is 168 KB; Universe watches package size per package).
- **Cross-OS wasm reproducibility caveat (already learned in Stage 1):** CI does NOT byte-diff the committed blobs (wasm output differs across host OS; blobs are committed from macOS, CI is ubuntu). CI rebuilds each crate fresh and runs the Typst suites against that build — functional coverage is the provenance gate. Keep the existing comment in `.github/workflows/ci.yml` (lines 30–33) intact.
- **Supercell bond caveat (design doc):** imported/precomputed `bonds` index unit-cell atoms, but rendering bonds the *displayed* set (which includes boundary images even at `supercell: (1,1,1)` for periodic structures — see `display-atoms`, `geometry.typ:12–52`). Therefore: parser-precomputed bonds are authoritative **for molecules only**; periodic structures always bond at render time (Typst `find-bonds` by default, plugin `detect_bonds` on the `engine: "wasm"` path). Never wire `record.bonds` into a periodic path.
- Typst tests run from the repo root: `make pkgroot && TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C <pkg> test`. Cargo commands run from the repo root (workspace). Rust tests: `cargo test --manifest-path <crate>/Cargo.toml`.
- **Working-tree hygiene:** pre-existing untracked/dirty files are NOT part of this stage (`AGENTS.md`, `.DS_Store`, `scenery/.DS_Store`, `scenery/examples/c60.typ`, `scenery/images/c60.png`, dirty `scenery/README.md`). Never `git add` them; every commit lists explicit paths. The workspace conversion moves the cargo target dir to the repo root — `/target/` must be gitignored in Task 1 and never committed.
- CBOR API note (verified in-session on Typst 0.14.2): `cbor.encode(value)` returns bytes; `cbor(bytes)` decodes (`cbor.decode` is deprecated). Typst dicts compare by content, not key order, so `assert.eq` between reassembled engine prims and pure-path prims is well-defined.

---

### Task 1: Cargo workspace + `scenery-engine` scaffold + CBOR boundary smoke test + build/CI wiring

**Files:**
- Create: `Cargo.toml` (workspace root), `scenery-engine/Cargo.toml`, `scenery-engine/src/lib.rs`, `scenery-engine/src/schema.rs`
- Create + commit: `scenery/plugin/scenery_engine.wasm`, `Cargo.lock` (workspace)
- Create: `scenery/src/engine.typ`, `scenery/tests/test-engine.typ`
- Modify: `wyckoff-io/Cargo.toml` (drop `[profile.release]`), `wyckoff/Makefile` (workspace target dir), `scenery/Makefile` (`plugin` target), root `Makefile` (`plugin` fan-out), `.gitignore` (`/target/`), `rust-toolchain.toml` (comment), `.github/workflows/ci.yml` (build + test the second crate)
- Delete: `wyckoff-io/Cargo.lock`, `wyckoff-io/.gitignore`

**Interfaces:**
- Produces (Rust): crate `scenery-engine` with `version() -> Vec<u8>` (`"scenery-engine 0.1.0"`), `echo(&[u8]) -> Vec<u8>`, and `sort_scene(&[u8]) -> Result<Vec<u8>, String>` — Task 1 stub: decode the full CBOR `Request`, return one `OutRec { i, d: 0.0 }` per prim in input order (schema round-trip proof; real keys land in Task 2).
- **The CBOR request schema** (the contract every later task targets; kebab-case keys):
  ```
  {
    camera: (mode: "2d")
          | (mode: "orthographic",  cos-az: f, sin-az: f, cos-el: f, sin-el: f)
          | (mode: "perspective",   cos-az: f, sin-az: f, cos-el: f, sin-el: f, distance: f),
    bsp:  bool,                      // Task 5 honors it; until then ignored
    cull: none | (seg-r-slack: f, point-r-slack: f, seg-w-frac: f, seg-d-slack: f),  // Task 7
    prims: [
      (k: "sphere", c: (x, y, z), r: f),
      (k: "seg",    a: (x, y, z), b: (x, y, z), w: f),   // w: resolved stroke width (cull only)
      (k: "edge",   a: (x, y, z), b: (x, y, z)),
      (k: "arrow",  a: (x, y, z), b: (x, y, z)),          // a = from, b = to
      (k: "face",   pts: ((x, y, z), ...), opaque: bool), // opaque = resolved fill-opacity == 0%
      (k: "label",  p: (x, y, z)),
    ],
  }
  ```
- **The CBOR response schema:** a CBOR array, **already in back-to-front draw order**:
  ```
  [ (i: int,            // index into the REQUEST prims array (styling lives Typst-side)
     d: float,          // the primitive's/fragment's depth key
     a?: (x,y,z), b?: (x,y,z),   // present iff a line fragment (seg/edge/arrow)
     head?: bool,                // present iff an arrow fragment (draw-head)
     pts?: ((x,y,z), ...),       // present iff a BSP face fragment
    ), ... ]
  ```
  Culled primitives simply never appear. A prim may appear multiple times (fragments).
- Produces (Typst, `scenery/src/engine.typ`): `engine-version()`, and `engine-sort(prepared, camera, theme: default-theme, bsp: true, cull: none)` — serializes, calls `sort_scene`, reassembles: `prepared.at(rec.i)` patched with the fragment geometry (`a`/`b` → `a`/`b`, or `from`/`to` for arrows; `head` → `draw-head`; `pts`), plus `depth: rec.d`. `prepared` must already be `_prepare-faces` output (meshes exploded, culling applied, `rear-face` tags in place — they ride along Typst-side by index).
- Consumes: `wasm-minimal-protocol` pattern from `wyckoff-io/src/lib.rs:1–43`; the plugin-relative-path pattern from `wyckoff/src/io.typ:8`.

- [ ] **Step 1: Convert to a workspace**

Create `/Users/liujinguo/tcode/scenery/Cargo.toml`:

```toml
# Cargo workspace for the monorepo's two WASM plugin crates (M4 design doc,
# "two wasm artifacts"): wyckoff-io ships in wyckoff/, scenery-engine in scenery/.
[workspace]
resolver = "2"
members = ["wyckoff-io", "scenery-engine"]

# Profiles must live at the workspace root (cargo ignores profiles declared in
# member crates). Lean-wasm settings, unchanged from the Stage-1 wyckoff-io blob.
[profile.release]
opt-level = "z"
lto = true
strip = true
panic = "abort"
```

In `wyckoff-io/Cargo.toml`, delete the entire `[profile.release]` block (lines 17–22). Then:

```bash
git rm wyckoff-io/Cargo.lock wyckoff-io/.gitignore
printf '/target/\n' >> .gitignore
```

Update the `rust-toolchain.toml` comment (keep `[toolchain]` unchanged) to name both blobs:

```toml
# Pins the toolchain so the committed plugin wasm blobs (wyckoff/plugin/
# wyckoff_io.wasm, scenery/plugin/scenery_engine.wasm) rebuild deterministically.
# CI rebuilds both crates fresh and runs the Typst suites against those builds
# (functional gate; cross-OS wasm output is not byte-reproducible).
# Bump `channel` only alongside rebuilt blobs.
```

- [ ] **Step 2: Scaffold the crate**

Create `scenery-engine/Cargo.toml`:

```toml
[package]
name = "scenery-engine"
version = "0.1.0"
edition = "2021"
license = "MIT"
description = "Host-agnostic projection, depth-sort, and BSP splitting for the scenery Typst package"
repository = "https://github.com/GiggleLiu/scenery"

[lib]
crate-type = ["cdylib", "rlib"]

[dependencies]
wasm-minimal-protocol = "0.1"
serde = { version = "1", features = ["derive"] }
ciborium = "0.2"
```

Create `scenery-engine/src/schema.rs` (the serialized contract; keep field names in exact sync with the schema above):

```rust
//! The CBOR boundary: request/response types. Host-agnostic — geometry plus the
//! two style-DERIVED geometric facts (face opacity, seg width) only; all colors,
//! gradients, opacity values, and themes stay on the Typst side.
use serde::{Deserialize, Serialize};

#[derive(Deserialize, Debug, Clone, Copy)]
#[serde(tag = "mode", rename_all = "kebab-case")]
pub enum Camera {
    #[serde(rename = "2d")]
    Flat,
    #[serde(rename = "orthographic", rename_all = "kebab-case")]
    Ortho { cos_az: f64, sin_az: f64, cos_el: f64, sin_el: f64 },
    #[serde(rename = "perspective", rename_all = "kebab-case")]
    Persp { cos_az: f64, sin_az: f64, cos_el: f64, sin_el: f64, distance: f64 },
}

#[derive(Deserialize, Debug, Clone, Copy)]
#[serde(rename_all = "kebab-case")]
pub struct Cull {
    pub seg_r_slack: f64,   // wyckoff occlude: sd < depth + seg_r_slack * r   (2.0)
    pub point_r_slack: f64, // covered by sphere: ed < depth + point_r_slack * r (1.0)
    pub seg_w_frac: f64,    // covered by seg stroke: dist2 < (seg_w_frac * w)^2 (0.45)
    pub seg_d_slack: f64,   // ... and ed < seg depth + seg_d_slack             (1.0)
}

#[derive(Deserialize, Debug, Clone)]
#[serde(tag = "k")]
pub enum Prim {
    #[serde(rename = "sphere")] Sphere { c: [f64; 3], r: f64 },
    #[serde(rename = "seg")]    Seg { a: [f64; 3], b: [f64; 3], w: f64 },
    #[serde(rename = "edge")]   Edge { a: [f64; 3], b: [f64; 3] },
    #[serde(rename = "arrow")]  Arrow { a: [f64; 3], b: [f64; 3] },
    #[serde(rename = "face")]   Face { pts: Vec<[f64; 3]>, opaque: bool },
    #[serde(rename = "label")]  Label { p: [f64; 3] },
}

#[derive(Deserialize, Debug)]
pub struct Request {
    pub camera: Camera,
    pub bsp: bool,
    pub cull: Option<Cull>,
    pub prims: Vec<Prim>,
}

/// One draw record; the response is `Vec<OutRec>` in back-to-front draw order.
#[derive(Serialize, Debug, PartialEq)]
pub struct OutRec {
    pub i: usize,
    pub d: f64,
    #[serde(skip_serializing_if = "Option::is_none")] pub a: Option<[f64; 3]>,
    #[serde(skip_serializing_if = "Option::is_none")] pub b: Option<[f64; 3]>,
    #[serde(skip_serializing_if = "Option::is_none")] pub head: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")] pub pts: Option<Vec<[f64; 3]>>,
}
```

Create `scenery-engine/src/lib.rs`:

```rust
#[cfg(target_arch = "wasm32")]
use wasm_minimal_protocol::*;

pub mod schema;

#[cfg(target_arch = "wasm32")]
initiate_protocol!();

#[cfg_attr(target_arch = "wasm32", wasm_func)]
pub fn version() -> Vec<u8> {
    format!("scenery-engine {}", env!("CARGO_PKG_VERSION")).into_bytes()
}

#[cfg_attr(target_arch = "wasm32", wasm_func)]
pub fn echo(input: &[u8]) -> Vec<u8> {
    input.to_vec()
}

/// Primitives + camera in (CBOR), depth-ordered primitives with depth keys out
/// (CBOR). Task 1 stub: schema round-trip in input order; Tasks 2-5 fill the
/// pipeline (cull -> clip -> bsp -> depth keys -> stable sort).
#[cfg_attr(target_arch = "wasm32", wasm_func)]
pub fn sort_scene(input: &[u8]) -> Result<Vec<u8>, String> {
    let req: schema::Request =
        ciborium::from_reader(input).map_err(|e| format!("scenery-engine: bad request: {e}"))?;
    let out: Vec<schema::OutRec> = (0..req.prims.len())
        .map(|i| schema::OutRec { i, d: 0.0, a: None, b: None, head: None, pts: None })
        .collect();
    let mut buf = Vec::new();
    ciborium::into_writer(&out, &mut buf)
        .map_err(|e| format!("scenery-engine: encode failed: {e}"))?;
    Ok(buf)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_reports_crate_semver() {
        assert_eq!(version(), b"scenery-engine 0.1.0".to_vec());
    }

    #[test]
    fn sort_scene_round_trips_the_schema() {
        // A hand-encoded request exercising every prim kind and camera field.
        let req = serde_json_like_cbor(); // helper below builds CBOR bytes via ciborium::Value
        let out = sort_scene(&req).expect("stub must decode the full schema");
        let recs: Vec<ciborium::Value> = ciborium::from_reader(&out[..]).unwrap();
        assert_eq!(recs.len(), 6);
    }
    // Build the request with ciborium::Value maps mirroring the documented schema
    // (all six prim kinds, orthographic camera with the four coefficients,
    // bsp: true, cull: null). Complete this helper mechanically.
    fn serde_json_like_cbor() -> Vec<u8> { /* ... */ unimplemented!() }
}
```

(Complete `serde_json_like_cbor` with `ciborium::value::Value::Map` literals for all six kinds — mechanical; the test's teeth are "the full documented schema deserializes".)

- [ ] **Step 3: Build targets**

`scenery/Makefile` — add `plugin` to `.PHONY` and append (mirror of `wyckoff/Makefile:30–40`, workspace-adjusted):

```make
PLUGIN_CRATE = ../scenery-engine
WASM_OUT = plugin/scenery_engine.wasm

plugin:
	cargo build --manifest-path ../Cargo.toml -p scenery-engine --release --target wasm32-unknown-unknown
	@mkdir -p plugin
	cp ../target/wasm32-unknown-unknown/release/scenery_engine.wasm $(WASM_OUT)
	@if command -v wasm-opt >/dev/null 2>&1; then \
	  echo "wasm-opt -Oz"; wasm-opt -Oz $(WASM_OUT) -o $(WASM_OUT); \
	else echo "wasm-opt not found, skipping (optional)"; fi
	@ls -l $(WASM_OUT)
```

`wyckoff/Makefile` — the workspace moves the target dir to the repo root; replace the two build lines of the `plugin` target (lines 34–36):

```make
plugin:
	cargo build --manifest-path ../Cargo.toml -p wyckoff-io --release --target wasm32-unknown-unknown
	@mkdir -p plugin
	cp ../target/wasm32-unknown-unknown/release/wyckoff_io.wasm $(WASM_OUT)
```

Root `Makefile` — replace the `plugin` target body (lines 33–35):

```make
plugin:
	@$(MAKE) -C wyckoff plugin
	@$(MAKE) -C scenery plugin
	@echo "Plugin(s) built."
```

- [ ] **Step 4: Build both crates, regenerate the lockfile, run cargo tests**

```bash
cargo generate-lockfile
cargo test --manifest-path wyckoff-io/Cargo.toml
cargo test --manifest-path scenery-engine/Cargo.toml
make -C wyckoff plugin && make -C scenery plugin
git status --short
```

Expected: both test suites pass; both `.wasm` files build; `git status` shows the new/changed files listed in this task **plus** `wyckoff/plugin/wyckoff_io.wasm` — **check whether the wyckoff blob changed**: the workspace conversion must not change its bytes on the same machine/toolchain (same rustc, same flags). If it DID change, run `git checkout -- wyckoff/plugin/wyckoff_io.wasm` and verify `make -C wyckoff test` still passes (the committed blob remains functionally valid); the blob is only recommitted in Task 6. `/target/` must be ignored (`git check-ignore target` prints `target`).

- [ ] **Step 5: Typst bridge + failing smoke test**

Create `scenery/src/engine.typ`:

```typ
// WASM accelerator bridge (issue #32): serializes prepared primitives + camera
// to CBOR, calls scenery-engine's sort_scene, and reassembles the returned
// draw-ordered records onto the original styled primitives by index.
// The engine is bytes-in/bytes-out and host-agnostic: all styling stays here.
#import "style.typ": default-theme, resolve-style

#let _engine = plugin("../plugin/scenery_engine.wasm")

/// Plugin version string (smoke check that the binary loads).
#let engine-version() = str(_engine.version())

#let _ser-pt(p) = p.map(float)

// The camera crosses the boundary as PRECOMPUTED trig coefficients so the
// engine performs only exactly-rounded arithmetic (+ - * / sqrt): sin/cos are
// libm-dependent and would break bit-identical depth keys across platforms.
#let _ser-camera(cam) = if cam.mode == "2d" { (mode: "2d") } else {
  (
    mode: cam.mode,
    cos-az: calc.cos(cam.azimuth), sin-az: calc.sin(cam.azimuth),
    cos-el: calc.cos(cam.elevation), sin-el: calc.sin(cam.elevation),
    ..if cam.mode == "perspective" { (distance: float(cam.distance)) } else { (:) },
  )
}

#let _ser-prim(p, theme) = {
  let k = p.kind
  if k == "sphere" { (k: k, c: _ser-pt(p.center), r: float(p.r)) }
  else if k == "seg" {
    (k: k, a: _ser-pt(p.a), b: _ser-pt(p.b), w: float(resolve-style(theme, p).w))
  } else if k == "edge" { (k: k, a: _ser-pt(p.a), b: _ser-pt(p.b)) }
  else if k == "arrow" { (k: k, a: _ser-pt(p.from), b: _ser-pt(p.to)) }
  else if k == "face" {
    (k: k, pts: p.pts.map(_ser-pt),
     opaque: resolve-style(theme, p).at("fill-opacity", default: 0%) == 0%)
  } else if k == "label" { (k: k, p: _ser-pt(p.at)) }
  else { panic("scenery engine: unsupported primitive kind: " + k) }
}

/// Depth-orders `prepared` primitives through the scenery-engine WASM plugin.
/// `prepared` MUST be `_prepare-faces` output (meshes exploded, face culling
/// applied, rear-face tags in place). Returns the same primitives — possibly
/// split into fragments — each with a `depth` key, in back-to-front draw order.
#let engine-sort(prepared, camera, theme: default-theme, bsp: true, cull: none) = {
  let req = cbor.encode((
    camera: _ser-camera(camera),
    bsp: bsp,
    cull: cull,
    prims: prepared.map(p => _ser-prim(p, theme)),
  ))
  let out = cbor(_engine.sort_scene(req))
  out.map(rec => {
    let p = prepared.at(rec.i)
    if "pts" in rec { p.insert("pts", rec.pts) }
    if "a" in rec {
      if p.kind == "arrow" { p.insert("from", rec.a); p.insert("to", rec.b) }
      else { p.insert("a", rec.a); p.insert("b", rec.b) }
    }
    if "head" in rec { p.insert("draw-head", rec.head) }
    (..p, depth: rec.d)
  })
}
```

Create `scenery/tests/test-engine.typ`:

```typ
#import "/src/engine.typ": engine-version, engine-sort
#import "/src/scene.typ": sphere, seg, edge, arrow, face, label
#import "/src/camera.typ": camera, camera-2d

// The second wasm artifact loads and reports its version.
#assert.eq(engine-version(), "scenery-engine 0.1.0")

// CBOR boundary smoke: every prim kind round-trips; the stub returns one
// record per prim carrying the ORIGINAL primitive's styling hooks (index
// reassembly works). Order/depth semantics land in Task 2.
#let ps = (
  sphere((0.0, 5.0, 0.0), 1.0, color: red),
  seg((0.0, 3.0, -1.0), (0.0, 3.0, 1.0)),
  edge((0.0, -1.0, -1.0), (0.0, -1.0, 1.0)),
  arrow((0.0, 2.0, 0.0), (1.0, 2.0, 0.0)),
  face(((-1.0, 1.0, -1.0), (1.0, 1.0, -1.0), (0.0, 1.0, 1.0))),
  label((0.0, 0.0, 0.0), [L]),
)
#let out = engine-sort(ps, camera(azimuth: 25deg, elevation: 15deg))
#assert.eq(out.len(), 6)
#assert.eq(out.map(p => p.kind), ("sphere", "seg", "edge", "arrow", "face", "label"))
#assert.eq(out.first().color, red, message: "styling must survive reassembly")
#assert(out.all(p => "depth" in p))

Engine boundary OK
```

Run: `make pkgroot && TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C scenery test`
Expected: **PASS** (the stub already satisfies the smoke test; the test was written against the schema first, and Steps 2–4 built the blob it loads). If the plugin fails to load, the path `../plugin/scenery_engine.wasm` is wrong — fix before proceeding.

- [ ] **Step 6: CI**

In `.github/workflows/ci.yml`: change the `Install Rust wasm target` step condition (line 25) to `if: matrix.package == 'wyckoff' || matrix.package == 'scenery'`, and insert after the wyckoff-io steps (after line 39):

```yaml
      # Same functional-gate pattern as wyckoff-io (see the note above): rebuild
      # the engine fresh and run scenery's typst suite (test-engine.typ + the
      # equivalence gates) against this build.
      - name: Build scenery-engine plugin
        if: matrix.package == 'scenery'
        run: make -C scenery plugin
      - name: Run scenery-engine tests
        if: matrix.package == 'scenery'
        run: cargo test --manifest-path scenery-engine/Cargo.toml
```

- [ ] **Step 7: Full-suite regression + zero-diff control**

```bash
make test
TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C scenery images
TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff images
git status --short scenery/images wyckoff/images
```

Expected: `All package test suites passed!`; only the pre-existing untracked `c60.png` appears (nothing rendered through the engine yet — negative control that the scaffold changed no behavior).

- [ ] **Step 8: Commit**

```bash
git add Cargo.toml Cargo.lock .gitignore rust-toolchain.toml wyckoff-io/Cargo.toml \
  scenery-engine/Cargo.toml scenery-engine/src/lib.rs scenery-engine/src/schema.rs \
  scenery/plugin/scenery_engine.wasm scenery/src/engine.typ scenery/tests/test-engine.typ \
  scenery/Makefile wyckoff/Makefile Makefile .github/workflows/ci.yml
git rm --cached wyckoff-io/Cargo.lock wyckoff-io/.gitignore 2>/dev/null; true
git commit -m "feat(scenery-engine): cargo workspace + engine scaffold + CBOR boundary (#32)"
```

---

### Task 2: Projection + depth-sort mirror + ordering-equivalence gate

**Files:**
- Create: `scenery-engine/src/camera.rs`, `scenery-engine/src/pipeline.rs`, `scenery-engine/tests/sort.rs`
- Modify: `scenery-engine/src/lib.rs` (route `sort_scene` through the pipeline)
- Modify: `scenery/tests/test-engine.typ`
- Rebuild + commit: `scenery/plugin/scenery_engine.wasm`

**Interfaces:**
- Produces (Rust, `camera.rs`) — the **exact** mirror of `scenery/src/camera.typ`:
  ```rust
  pub struct Proj { pub sx: f64, pub sy: f64, pub depth: f64 }
  impl Camera {
      /// Mirror of camera.typ:76-92 `project`, with the trig replaced by the
      /// shipped coefficients. Same expression order:
      ///   x1 = x*ca + y*sa;  y1 = -x*sa + y*ca;
      ///   sy = -y1*se + z*ce;  depth = y1*ce + z*se;
      /// perspective: s = distance/(distance-depth); sx = x1*s, sy = sy*s,
      /// depth UNSCALED. 2d: (sx: x, sy: y, depth: 0.0).
      pub fn project(&self, p: [f64; 3]) -> Result<Proj, String>;
      /// Mirror of camera.typ:50-58 `project-scale`: 1.0 unless perspective;
      /// perspective: distance/(distance-depth), Err when
      /// !(denom > 1e-9 * distance) with a message containing
      /// "at or behind the perspective camera" (mirrors the Typst assert).
      pub fn scale_at(&self, depth: f64) -> Result<f64, String>;
  }
  ```
- Produces (Rust, `pipeline.rs`): `pub fn run(req: &Request) -> Result<Vec<OutRec>, String>` — Task 2 scope: depth keys + stable sort only (no cull/clip/bsp yet). Mirrors:
  - `_mid` (render.typ:70), `_centroid` (:73 — **left fold**, then scale by `1.0 / n`), `_depth-point` (:76–83): sphere → center, seg/edge → midpoint of `a`,`b`, arrow → midpoint, face → centroid of `pts`;
  - `sort-prims` (render.typ:499–507): label depth is the literal `1e9`; every other prim projects its depth point; **stable sort ascending** by depth (`sort_by(|x, y| x.d.total_cmp(&y.d))` over the input-order vec). Depth keys must be finite — non-finite → `Err`.
  - Output: `OutRec { i, d, .. }` with no geometry overrides (nothing splits yet).
- Consumes: `schema.rs` (Task 1).

- [ ] **Step 1: Write the failing Rust pinning tests**

`scenery-engine/tests/sort.rs` — transcribe the documented 4-prim scene from `scenery/tests/test-render.typ:12–49` (its depth keys are hand-worked there: edge −1, face 1, seg 3, sphere 5 under the azimuth=elevation=0 camera, whose coefficients are exactly `ca=1, sa=0, ce=1, se=0`):

```rust
use scenery_engine::schema::*;
use scenery_engine::pipeline;

fn cam0() -> Camera { Camera::Ortho { cos_az: 1.0, sin_az: 0.0, cos_el: 1.0, sin_el: 0.0 } }
fn req(camera: Camera, prims: Vec<Prim>) -> Request { Request { camera, bsp: true, cull: None, prims } }

#[test]
fn documented_scene_sorts_back_to_front() {
    // edge y=-1, face centroid y=1, seg y=3, sphere y=5 (test-render.typ:22-27)
    let prims = vec![
        Prim::Edge { a: [0.0, -1.0, -1.0], b: [0.0, -1.0, 1.0] },
        Prim::Face { pts: vec![[-1.0, 1.0, -1.0], [1.0, 1.0, -1.0], [0.0, 1.0, 1.0]], opaque: true },
        Prim::Seg { a: [0.0, 3.0, -1.0], b: [0.0, 3.0, 1.0], w: 0.12 },
        Prim::Sphere { c: [0.0, 5.0, 0.0], r: 1.0 },
    ];
    let out = pipeline::run(&req(cam0(), prims)).unwrap();
    assert_eq!(out.iter().map(|r| r.i).collect::<Vec<_>>(), vec![0, 1, 2, 3]);
    assert_eq!(out.iter().map(|r| r.d).collect::<Vec<_>>(), vec![-1.0, 1.0, 3.0, 5.0]);
}

#[test]
fn shuffled_input_recovers_the_same_order() { /* same prims reversed; indices 3,2,1,0 */ }

#[test]
fn labels_paint_last_with_1e9() {
    // sphere at y=100 vs label: label sorts last with d == 1e9 (render.typ:501)
}

#[test]
fn stable_sort_preserves_input_order_on_ties() {
    // two spheres at identical depth: output indices in input order (Typst
    // .sorted is stable; the engine must match).
}

#[test]
fn perspective_depth_keys_are_unscaled() {
    // Persp{ca:1,sa:0,ce:1,se:0,distance:10}, sphere at y=5: d == 5.0 exactly
    // (Stage-3 pinned convention: the depth key stays the unscaled view depth).
}

#[test]
fn flat_camera_keeps_input_order() {
    // 2d: every non-label depth is 0.0; output order == input order.
}

#[test]
fn behind_perspective_camera_errors() {
    // distance 2, point at y=100: Err containing "at or behind the perspective camera"
}
```

Run: `cargo test --manifest-path scenery-engine/Cargo.toml` — Expected: FAIL (`pipeline` module missing).

- [ ] **Step 2: Implement `camera.rs` + `pipeline.rs`**

Transcribe per the Interfaces block. The pipeline for Task 2:

```rust
pub fn run(req: &Request) -> Result<Vec<OutRec>, String> {
    let cam = &req.camera;
    let mut keyed: Vec<OutRec> = Vec::with_capacity(req.prims.len());
    for (i, p) in req.prims.iter().enumerate() {
        let d = match p {
            Prim::Label { .. } => 1e9,
            _ => cam.project(depth_point(p)).?.depth,
        };
        if !d.is_finite() { return Err(format!("scenery-engine: non-finite depth for primitive {i}")); }
        keyed.push(OutRec { i, d, a: None, b: None, head: None, pts: None });
    }
    keyed.sort_by(|x, y| x.d.total_cmp(&y.d)); // stable, mirrors Typst .sorted(key:)
    Ok(keyed)
}
```

with `depth_point` mirroring render.typ:76–83 and `centroid` folding left then scaling by `1.0 / pts.len() as f64` (mirror `vscale(fold(vadd), 1/n)` — Typst divides `1 / n` first then multiplies each component; mirror exactly: compute `s = 1.0 / (pts.len() as f64)` and multiply each summed component by `s`).

Run: `cargo test --manifest-path scenery-engine/Cargo.toml` — Expected: all pass.

- [ ] **Step 3: The Typst ordering-equivalence gate (level (a) of the layered gate)**

Rebuild the blob: `make -C scenery plugin`. Then replace the Task-1 smoke block of `scenery/tests/test-engine.typ` (keep the version assert) with:

```typ
#import "/src/engine.typ": engine-version, engine-sort
#import "/src/scene.typ": sphere, seg, edge, arrow, face, label, build-scene, mesh
#import "/src/shape.typ": uv-sphere
#import "/src/camera.typ": camera, camera-2d
#import "/src/render.typ": sort-prims, _prepare-faces

#assert.eq(engine-version(), "scenery-engine 0.1.0")

// ============ ORDERING-EQUIVALENCE GATE, level (a) ============
// Scenes where NEITHER path splits anything: engine output must be EXACTLY
// equal (assert.eq on full dicts, depth included) to the pure path. Until
// Task 3 the engine does not clip, so the pure comparator is sort-prims over
// _prepare-faces output (the same keys-and-stable-sort stage the engine mirrors).
#let gate(prims, cam) = {
  let prepared = _prepare-faces(prims, cam)
  assert.eq(engine-sort(prepared, cam), sort-prims(prepared, cam))
}

// The documented 4-prim scene (test-render.typ) + its shuffle, exact depths.
#let cam0 = camera(azimuth: 0deg, elevation: 0deg)
#let ps = (
  edge((0, -1, -1), (0, -1, 1)),
  face(((-1, 1, -1), (1, 1, -1), (0, 1, 1))),
  seg((0, 3, -1), (0, 3, 1)),
  sphere((0, 5, 0), 1),
  label((0, 0, 0), [L]),
)
#gate(ps, cam0)
#gate(ps.rev(), cam0)

// Generic camera: the engine consumes the SAME cos/sin values Typst computed,
// so depth keys are bit-identical, not merely close.
#gate(ps, camera(azimuth: 25deg, elevation: 15deg))
#gate(ps, camera(azimuth: -73deg, elevation: 41deg))

// Perspective and 2d cameras.
#gate(ps, camera(azimuth: 25deg, elevation: 15deg, mode: "perspective", distance: 30.0))
#gate(((sphere((0, 0), 1), seg((1, 1), (2, 2)), label((0, 3), [x]))), camera-2d())

// Meshes: _prepare-faces explodes + culls Typst-side; the engine keys the
// resulting faces by centroid exactly like sort-prims.
#let mesh-scene = (uv-sphere((0, 0, 0), 1, segments: 6, rings: 3), sphere((0, 4, 0), 0.5))
#gate(mesh-scene, camera(azimuth: 25deg, elevation: 15deg))

Engine sort OK
```

Run: `TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C scenery test`
Expected: `All tests passed!`. **This is the first bit-identity checkpoint: if any `gate` fails with near-equal depths (last-ulp), STOP and report per the Global Constraints fallback — do not loosen the assert yourself.**

- [ ] **Step 4: Zero-diff control + commit**

```bash
TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C scenery images && git status --short scenery/images
git add scenery-engine/src/lib.rs scenery-engine/src/camera.rs scenery-engine/src/pipeline.rs \
  scenery-engine/tests/sort.rs scenery/plugin/scenery_engine.wasm scenery/tests/test-engine.typ
git commit -m "feat(scenery-engine): projection + depth-sort mirror with ordering-equivalence gate (#32)"
```

(Expected `git status`: only the untracked c60.png.)

---

### Task 3: Line-clipping mirror (`_clip-lines` port) — fragment parity

**Files:**
- Create: `scenery-engine/src/clip.rs`, `scenery-engine/tests/clip.rs`
- Modify: `scenery-engine/src/pipeline.rs` (insert clip before keys/sort)
- Modify: `scenery/tests/test-engine.typ`
- Rebuild + commit: `scenery/plugin/scenery_engine.wasm`

**Interfaces:**
- Produces (Rust, `clip.rs`): `pub fn clip_lines(prims: &[Prim], cam: &Camera) -> Result<Vec<Frag>, String>` where `Frag { i: usize, prim: FragGeom }` carries either a pass-through reference or a line fragment `(a, b, head: Option<bool>)`. **Function-by-function mirror table** (transcribe each, same expression order, citing the source in a comment above each Rust fn):

  | Rust fn | Mirrors (`scenery/src/render.typ`) | Notes |
  |---|---|---|
  | `quadratic_interval` | `_quadratic-interval` :194–206 | `sqrt` is exactly rounded; keep the `disc <= 0` early-outs |
  | `depth_half` | `_depth-half` :210–227 | mirror the `dh == 0` branch with exact `==` |
  | `projected_sphere` | `_projected-sphere` :237–242 | uses `project` + `scale_at` (perspective radius) |
  | `overlap1`, `line_bbox_overlaps_disk` | :244–248 | `f64::min`/`max` |
  | `line_sphere_occlusion` | `_line-sphere-occlusion` :250–270 | returns `(hidden, disk)` exactly |
  | `merge_intervals` | `_merge-intervals` :272–291 | sort by `lo` with stable `total_cmp`; `eps = 1e-12` |
  | `lerp_point` | `_lerp-point` :293 | `a*(1-t) + b*t` per component, same order |
  | `cross2`, `point_in_polygon` | :295–312 | integer-free, direct |
  | `face_occluder` | `_face-occluder` :316–344 | `opaque` comes from the schema flag, NOT resolve-style; planarity eps `1e-8 * |n| * scale`, view-dot eps `1e-12 * |n|`; also mirror `_face-normal` :125–142 (first non-degenerate cross product; **no mesh-center reorientation** — the flag never crosses the boundary, and every plane-side use below is orientation-invariant: numerator and denominator flip together) |
  | `line_bbox_overlaps_face` | :346–349 | |
  | `line_face_interaction` | `_line-face-interaction` :353–401 | cuts + hidden intervals; `param-eps 1e-12`; the `s0 * s1 < 0` plane crossing; midpoint point-in-polygon test; `depth-eps = 1e-12 * max(|b-a|, face.scale)` |
  | `line_fragment` | `_line-fragment` :405–416 | arrow: `head = interval.1 >= 1 - eps` |
  | `clip_lines` | `_clip-lines` :424–485 | the full loop: spheres list, face-occluder list (skip `None`s), per-line: hidden/cuts accumulation, `merge_intervals`, cut dedup (`t - last > eps`), visible-interval scan with the advancing `hidden-index`, fragments emitted in ascending-interval order **at the parent's position** |

  Key semantic to preserve (it drives the reassembly contract): on the pure path **every** seg/edge/arrow passes through `_line-fragment`, even unoccluded ones (interval `(0,1)` — endpoints recomputed via `lerp` which is IEEE-exact at t=0/1, and arrows ALWAYS gain `draw-head`). The engine mirrors this: every surviving line emits fragments with `a`/`b` set (and `head` for arrows); non-line prims pass through with no overrides.
- Modifies `pipeline::run` order: `clip_lines` → depth keys (a fragment's key is its own midpoint) → stable sort over the emission order.
- One deliberate scope note: `_prepare-faces` (render.typ:158–189) is **not** mirrored — the Typst caller runs it before serializing (it needs `resolve-style` for cull policy and opacity). The pure-path comparator in the tests is therefore `sort-prims(_clip-lines(prims, cam, theme), cam)`, whose internal `_prepare-faces` sees the same faces.

- [ ] **Step 1: Write the failing Rust pinning tests**

`scenery-engine/tests/clip.rs` — transcribe every `_clip-lines` pin from `scenery/tests/test-render.typ:58–150` against `cam0`:
1. center bond `sphere(0,0,0 r1) + seg((0,0,0)→(2,0,0))` → exactly 1 seg fragment, `a.x` within `1e-6` of `1.0`;
2. rear edge inside the disk → 0 fragments;
3. front edge nearer than the sphere surface → 1 fragment;
4. sloped depth-crossing edge → 2 fragments; the later-sorted one has `d > 0`;
5. tiny-scale (r `1e-6`) → 1 fragment, `a.x ≈ 1e-6` within `1e-12`;
6. two disjoint spheres split one seg → 3 fragments;
7. arrow through a sphere → 2 fragments, `head == Some(false)` then `Some(true)`; occluded tip → 1 fragment `head Some(false)`; two spheres → 3 fragments, exactly one head, on the last;
8. broad-phase: a distant sphere leaves an arrow's fragment geometry **exactly equal** (`==` on the f64 arrays) to the no-sphere case;
9. opaque face hides the crossing interval of a line behind it (build from `_line-face-interaction` semantics: line from `(0,-2,0)` to `(0,2,0)` behind/through a face at `y=1`… pin count + fragment endpoints via the plane crossing `t = s0/(s0-s1)`);
10. translucent face (`opaque: false`) contributes CUTS but hides nothing: same line → more fragments, total visible length 1.0.

Run: `cargo test --manifest-path scenery-engine/Cargo.toml` — Expected: FAIL (module missing).

- [ ] **Step 2: Implement `clip.rs` per the mirror table; wire into `pipeline.rs`; make the Rust tests pass**

- [ ] **Step 3: Upgrade the Typst gate to the full pipeline**

`make -C scenery plugin`. In `scenery/tests/test-engine.typ`, extend the render import with `, _clip-lines` and redefine the gate + add cutting scenes:

```typ
// ============ FULL-PIPELINE EQUALITY (fragments included) ============
// The engine now mirrors _clip-lines: for any scene (cutting or not), engine
// output must be EXACTLY equal to sort-prims(_clip-lines(..)) — fragments,
// draw-head flags, and depth keys bit-for-bit.
#let full-gate(prims, cam) = assert.eq(
  engine-sort(_prepare-faces(prims, cam), cam),
  sort-prims(_clip-lines(prims, cam), cam),
)

#full-gate(ps, cam0)                                  // the Task-2 scenes still hold
#full-gate(ps, camera(azimuth: 25deg, elevation: 15deg))

// Fragment-cutting scenes (the reason the naive ordering gate is ill-defined):
#let cutting = (
  sphere((0, 0, 0), 1), sphere((2.5, 1, 0.5), 0.7),
  seg((-2, 0, 0), (4, 0, 0)),
  arrow((-2, 0.4, 0.8), (4, 0.4, 0.8)),
  edge((-2, -0.5, -0.5), (4, 1.5, 0.5)),
  face(((1, -1, -1.2), (3, -1, -1.2), (3, 2, -1.2), (1, 2, -1.2)), fill-opacity: 0%),
  face(((-1, 0.5, -1), (1.5, 0.5, -1), (0.2, 0.5, 1.5))),  // translucent: cuts only
)
#full-gate(cutting, cam0)
#full-gate(cutting, camera(azimuth: 25deg, elevation: 15deg))
#full-gate(cutting, camera(azimuth: 25deg, elevation: 15deg, mode: "perspective", distance: 20.0))
#full-gate(mesh-scene + (seg((-2, 0, 0), (2, 0, 0)),), camera(azimuth: 25deg, elevation: 15deg))
```

Run: `TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C scenery test`
Expected: `All tests passed!`. **Second bit-identity checkpoint — same STOP rule.** This gate failing on fragment endpoints (not depths) means an expression-order divergence in the clip transcription: diff the failing fragment against the mirror table, fix the transcription; never "fix" by loosening.

- [ ] **Step 4: Zero-diff control + commit**

```bash
TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C scenery images && git status --short scenery/images
git add scenery-engine/src/clip.rs scenery-engine/src/pipeline.rs scenery-engine/tests/clip.rs \
  scenery/plugin/scenery_engine.wasm scenery/tests/test-engine.typ
git commit -m "feat(scenery-engine): line-clipping mirror with full-pipeline fragment parity (#32)"
```

---

### Task 4: Opt-in wiring in the scenery core + pixel-equivalence gate

**Files:**
- Modify: `scenery/src/render.typ` (`scene-group`, `render-scene`), `scenery/lib.typ` (export `engine-sort`, `engine-version`)
- Create: `scenery/tests/equiv/equiv-scene.typ`, `scenery/tests/errors/engine-bogus.typ`
- Modify: `scenery/Makefile` (`test-equiv` target, folded into `test`)
- Modify: `scenery/tests/test-engine.typ`

**Interfaces:**
- Produces (Typst): `scene-group(scene, camera, theme:, unit:, axes:, legend:, colorbar:, register-anchors:, engine: "typst", engine-cull: none)` and `render-scene(scene, camera, width:, theme:, axes:, legend:, colorbar:, engine: "typst", engine-cull: none)`. `engine` ∈ `("typst", "wasm")`, asserted with a clear message. The engine branch (in `scene-group`, replacing only the `records =` line at render.typ:664–666):
  ```typ
  let ordered = if engine == "wasm" {
    import "engine.typ": engine-sort
    engine-sort(_prepare-faces(scene.prims, camera, theme: theme), camera,
      theme: theme, cull: engine-cull)
  } else {
    sort-prims(_clip-lines(scene.prims, camera, theme: theme), camera)
  }
  let records = ordered.map(p => _record(camera, unit, theme, p))
  ```
  The `import` is **scoped inside the branch** so the pure path never loads the wasm blob. `engine-cull` is forwarded verbatim (used by wyckoff in Task 7; `none` disables culling).
- Produces (Makefile): `test-equiv` — compiles `tests/equiv/equiv-scene.typ` twice via `sys.inputs` and `cmp`s the PNGs (level (b) of the layered gate). `test` depends on it so CI runs it automatically via the existing `Run tests` step.
- Consumes: `engine-sort` (Tasks 1–3).

- [ ] **Step 1: Failing error test + API assert**

Create `scenery/tests/errors/engine-bogus.typ`:

```typ
// expected: engine must be "typst" or "wasm"
#import "/lib.typ": *
#let sc = build-scene(sphere((0, 0, 0), 1))
#render-scene(sc, camera(), engine: "gpu")
```

Run: `TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C scenery test` — Expected: FAIL (`unexpected argument: engine`).

- [ ] **Step 2: Implement the wiring**

Edit `scene-group` and `render-scene` per the Interfaces block (add the two named params + the assert `engine in ("typst", "wasm")` with message `"scenery: engine must be \"typst\" or \"wasm\", got " + repr(engine)`; `render-scene` forwards both). In `scenery/lib.typ`, extend the render import line with nothing and add:

```typ
// WASM geometry accelerator (opt-in; pure Typst is the default and fallback).
#import "src/engine.typ": engine-sort, engine-version
```

- [ ] **Step 3: The pixel-equivalence fixture**

Create `scenery/tests/equiv/equiv-scene.typ`:

```typ
// Pixel-equivalence gate (M4 design doc, "Accelerator equivalence"): this file
// compiles twice — --input engine=typst and --input engine=wasm — and the two
// PNGs must be byte-identical (scenery/Makefile `test-equiv`). Scenes cover:
// fragment-cutting lines (both paths cut identically), opaque + translucent
// faces, meshes, perspective, and translucent NON-intersecting solids (the
// BSP negative control at pixel level once Task 5 lands).
#import "/lib.typ": *
#let eng = sys.inputs.at("engine", default: "typst")
#set page(width: auto, height: auto, margin: 0.5cm)

#let cam = camera(azimuth: 25deg, elevation: 15deg)
#let sc1 = build-scene(
  sphere((0, 0, 0), 1, color: rgb("#c44e52")),
  sphere((2.5, 1, 0.5), 0.7, color: rgb("#4c72b0")),
  seg((-2, 0, 0), (4, 0, 0)),
  arrow((-2, 0.4, 0.8), (4, 0.4, 0.8)),
  edge((-2, -0.5, -0.5), (4, 1.5, 0.5)),
  face(((1, -1, -1.2), (3, -1, -1.2), (3, 2, -1.2), (1, 2, -1.2)),
    color: rgb("#55a868"), fill-opacity: 0%),
  label((0, 1.6, 1.2), [cut]),
)
#render-scene(sc1, cam, engine: eng, width: 7cm)

#let sc2 = build-scene(
  uv-sphere((0, 0, 0), 1, color: rgb("#4c72b0"), fill-opacity: 45%),
  prism(((2.2, -0.5, -0.5), (3.2, -0.5, -0.5), (3.2, 0.5, -0.5), (2.2, 0.5, -0.5)),
    (0, 0, 1), color: rgb("#dd8452"), fill-opacity: 45%),
  seg((-1.5, 0, 0), (3.5, 0, 0)),
)
#render-scene(sc2, cam, engine: eng, width: 7cm)

#render-scene(sc1, camera(azimuth: 25deg, elevation: 15deg, mode: "perspective", distance: 12.0),
  engine: eng, width: 7cm)
```

In `scenery/Makefile`, add `test-equiv` to `.PHONY`, make `test` depend on it (`test: manual test-equiv`), and append:

```make
# Accelerator pixel-equivalence gate (issue #32): the same fixture through the
# pure-Typst and wasm paths must render byte-identically. tests/*.png is
# gitignored, so the outputs never dirty the tree.
test-equiv:
	$(TYPST) --format png --ppi 144 --input engine=typst tests/equiv/equiv-scene.typ tests/equiv-typst.png
	$(TYPST) --format png --ppi 144 --input engine=wasm  tests/equiv/equiv-scene.typ tests/equiv-wasm.png
	cmp tests/equiv-typst.png tests/equiv-wasm.png
	@echo "engine=wasm and engine=typst render pixel-identically"
```

- [ ] **Step 4: Data-level negative control (the opt-in changes nothing by default)**

Append to `scenery/tests/test-engine.typ`:

```typ
// The default path is untouched: engine: "typst" output of scene-group is the
// pre-Stage-4 expression by construction (same code branch); pin the public
// entry compiles both ways on the same scene.
#let _ = scenery-smoke() // replace with: render-scene(sc, cam) and render-scene(sc, cam, engine: "wasm") smoke-compiled via a small scene
```

(Concretely: build a 3-prim scene, call `render-scene(sc, cam)` and `render-scene(sc, cam, engine: "wasm")` — both must compile; the pixel gate carries the equality burden.)

- [ ] **Step 5: Run everything**

```bash
TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C scenery test
```

Expected: `All tests passed!` **including** `test-equiv`'s `cmp` (silent = identical) and the new error test. **Third bit-identity checkpoint (pixel level) — same STOP rule.** Then the zero-diff control:

```bash
TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C scenery images && git status --short scenery/images
make test
```

Expected: only untracked c60.png; all packages green.

- [ ] **Step 6: Commit**

```bash
git add scenery/src/render.typ scenery/lib.typ scenery/tests/equiv/equiv-scene.typ \
  scenery/tests/errors/engine-bogus.typ scenery/tests/test-engine.typ scenery/Makefile
git commit -m "feat(scenery): opt-in engine=\"wasm\" render path + pixel-equivalence gate (#32)"
```

---

### Task 5: BSP splitting for intersecting translucent faces (issue #33)

**Files:**
- Create: `scenery-engine/src/bsp.rs`, `scenery-engine/tests/bsp.rs`
- Modify: `scenery-engine/src/pipeline.rs` (insert BSP between clip and keys)
- Modify: `scenery/tests/test-engine.typ`
- Create: `scenery/examples/bsp.typ`; create + commit `scenery/images/bsp.png`
- Rebuild + commit: `scenery/plugin/scenery_engine.wasm`

**Interfaces:**
- Produces (Rust, `bsp.rs`): `pub fn split_translucent(faces: Vec<FaceFrag>) -> Vec<FaceFrag>` where `FaceFrag { i: usize, pts: Vec<[f64;3]>, split: bool }`. **The precise algorithm (deterministic, splits only where faces actually intersect):**
  1. **Candidates:** face prims with `opaque == false`, ≥ 3 vertices, planar (reuse `face_occluder`'s planarity test: eps `1e-8 · |n| · scale`) and a non-degenerate normal (`_face-normal` mirror). Everything else passes through untouched.
  2. **Intersection predicate** `faces_intersect(f, g)`: with `eps = 1e-9 · max(scale_f, scale_g)` (`scale` = max vertex distance from the first vertex, as in `_face-occluder`), (i) `g` has vertices strictly on BOTH sides of `plane(f)` (signed distance > eps and < −eps); (ii) the chord `plane(f) ∩ polygon(g)` — the segment between the crossing points of g's edges with the plane — intersects `polygon(f)` (2D test in the plane: either chord endpoint inside `polygon(f)` via `point_in_polygon` on projected coordinates, or a proper chord/edge crossing via `cross2` orientation tests). Both conditions ⇒ the polygons genuinely interpenetrate. The chord is the SAME segment viewed from either face, so the predicate is symmetric in outcome.
  3. **Partition strategy:** build the undirected intersection graph over candidates; take connected components (deterministic order: components discovered by ascending lowest face index, BFS over ascending indices). Components of size 1 pass through **untouched** (`split: false` — the negative control). Within a component, iterate partition faces `p` in **ascending original index**; for each, scan the current fragment list (in order); every fragment `g` with `g.i != p.i` satisfying `faces_intersect(polygon(p), g)` is split by `plane(p)`: classify each vertex by signed distance with eps snapping (|d| ≤ eps ⇒ on-plane, emitted to both sides); crossing edges insert the interpolated vertex at `t = d0 / (d0 - d1)` into both rings. Replace `g` in place by (negative-side piece, positive-side piece) — **negative side of `plane(p)`'s normal first** (the deterministic emission tie-break). Pieces with < 3 vertices or squared-area below `(eps · scale)²` are dropped (invisible slivers).
  4. This is BSP-style mutual-plane splitting with the ordering delegated to the depth sort (the design doc's contract: "the engine returns *ordered, split* primitives with depth keys"): after splitting, every fragment lies entirely on one side of every partner plane it crossed, which removes the cyclic large-piece misordering; fragments then re-enter the standard centroid depth keys + stable sort.
- Pipeline order becomes: cull (Task 7) → `clip_lines` (against the ORIGINAL faces — the pure path clips against unsplit faces, and line cuts must stay bit-identical) → `split_translucent` → depth keys (a face fragment keys on its own centroid) → stable sort. Face fragments emit `OutRec` with `pts: Some(..)` **only when actually split** (`split: true`), so unsplit faces reassemble bit-identically Typst-side.
- Consumes: `clip.rs` geometry helpers (`face plane/normal`, `point_in_polygon`, `cross2`).

- [ ] **Step 1: Write the failing Rust tests**

`scenery-engine/tests/bsp.rs` — the canonical analytic scene: two unit-ish rectangles crossing along the x-axis,

```rust
// Q1 in the z=0 plane (normal ±z), Q2 in the y=0 plane (normal ±y); they
// interpenetrate along the segment x in [-1.5, 1.5], y=z=0.
fn q1() -> Prim { Prim::Face { pts: vec![[-1.5,-1.0,0.0],[1.5,-1.0,0.0],[1.5,1.0,0.0],[-1.5,1.0,0.0]], opaque: false } }
fn q2() -> Prim { Prim::Face { pts: vec![[-1.5,0.0,-1.0],[1.5,0.0,-1.0],[1.5,0.0,1.0],[-1.5,0.0,1.0]], opaque: false } }
```

with camera `Ortho { cos_az: 1.0, sin_az: 0.0, cos_el: 3f64.sqrt()/2.0, sin_el: 0.5 }` (elevation 30°, depth direction `(0, cos30, sin30)`):
1. **Split count:** `pipeline::run` on `[q1, q2]` returns exactly 4 face records, all with `pts: Some(..)`, two per input index.
2. **Plane-side invariant:** every fragment's vertices lie entirely on one side (within eps) of the OTHER face's plane.
3. **Hand-pinned depth keys** (centroids `(0, ∓0.5, 0)` and `(0, 0, ∓0.5)`): sorted order must be Q1-back (`d = −0.5·cos30 ≈ −0.4330127…`), Q2-bottom (`−0.25`), Q2-top (`+0.25`), Q1-front (`+0.4330127…`) — assert with `1e-12` tolerance — and verify the painter-correctness meaning: each later-drawn fragment is on the viewer side of every earlier overlapping fragment's plane.
4. **Negative control (no spurious splits):** translate Q2 to `y = 2.5` (disjoint) → output records carry `pts: None` and equal the no-BSP pipeline output exactly (`OutRec` PartialEq). Also: two PARALLEL translucent faces (coplanar-offset) → untouched; a translucent face + an OPAQUE crossing face → untouched (BSP is translucent-only); a translucent face whose PLANE crosses another polygon but whose polygon does not (offset far along x) → untouched (the chord test has teeth).
5. **Three-face chain:** Q1, Q2, and Q3 (plane x=0.2, crossing both) → every output fragment satisfies invariant 2 against both partners; fragment count is deterministic across two runs (run twice, assert equal output).

Run: `cargo test --manifest-path scenery-engine/Cargo.toml` — Expected: FAIL.

- [ ] **Step 2: Implement `bsp.rs` per the algorithm spec; wire into the pipeline; make the tests pass**

- [ ] **Step 3: Typst-level controls**

`make -C scenery plugin`. Append to `scenery/tests/test-engine.typ`:

```typ
// ============ BSP (issue #33) ============
// Intersecting translucent faces are split before ordering (level (c) of the
// gate: structural asserts + reviewed example, never pixel-diffed vs pure).
#let vq1 = face(((-1.5, -1, 0), (1.5, -1, 0), (1.5, 1, 0), (-1.5, 1, 0)), color: rgb("#4c72b0"))
#let vq2 = face(((-1.5, 0, -1), (1.5, 0, -1), (1.5, 0, 1), (-1.5, 0, 1)), color: rgb("#dd8452"))
#let bsp-cam = camera(azimuth: 0deg, elevation: 30deg)
#let split = engine-sort((vq1, vq2), bsp-cam)
#assert.eq(split.len(), 4, message: "two crossing translucent quads split into four fragments")
#assert(split.all(p => p.kind == "face" and p.pts.len() >= 3))
// styling rides through reassembly onto every fragment
#assert.eq(split.map(p => p.color).dedup().len(), 2)

// NEGATIVE CONTROL: non-intersecting translucent faces — BSP output is exactly
// the pure pipeline (no spurious splits; also enforced at pixel level by
// test-equiv scene 2 on every run).
#let vq2-apart = face(((-1.5, 2.5, -1), (1.5, 2.5, -1), (1.5, 2.5, 1), (-1.5, 2.5, 1)), color: rgb("#dd8452"))
#assert.eq(
  engine-sort(_prepare-faces((vq1, vq2-apart), bsp-cam), bsp-cam),
  sort-prims(_clip-lines((vq1, vq2-apart), bsp-cam), bsp-cam),
)

// bsp: false reproduces the plain painter's sort even on the crossing scene.
#assert.eq(
  engine-sort(_prepare-faces((vq1, vq2), bsp-cam), bsp-cam, bsp: false),
  sort-prims(_clip-lines((vq1, vq2), bsp-cam), bsp-cam),
)
```

- [ ] **Step 4: The before/after example (`make images` deliverable of #33)**

Create `scenery/examples/bsp.typ`:

```typ
#import "/lib.typ": *

#set page(width: auto, height: auto, margin: 0.6cm)
#set text(font: "New Computer Modern", size: 10pt)

// Two interpenetrating translucent panes. The plain painter's sort (left) must
// pick ONE pane to paint entirely on top — wrong on one side of the crossing.
// The engine's BSP split (right) layers each half correctly.
#let panes = build-scene(
  face(((-1.5, -1, 0), (1.5, -1, 0), (1.5, 1, 0), (-1.5, 1, 0)),
    color: rgb("#4c72b0"), fill-opacity: 45%),
  face(((-1.5, 0, -1), (1.5, 0, -1), (1.5, 0, 1), (-1.5, 0, 1)),
    color: rgb("#dd8452"), fill-opacity: 45%),
)
#let v = camera(azimuth: 35deg, elevation: 20deg)
#grid(
  columns: 2, column-gutter: 1cm,
  align(center)[
    #render-scene(panes, v, width: 6cm)
    Painter's sort (`engine: "typst"`): mis-ordered
  ],
  align(center)[
    #render-scene(panes, v, engine: "wasm", width: 6cm)
    BSP split (`engine: "wasm"`): correct layering
  ],
)
```

```bash
TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C scenery test
TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C scenery examples
TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C scenery images
git status --short scenery/images
```

Expected: all tests pass (including `test-equiv` — the BSP negative control at pixel level); only NEW `bsp.png` (plus untracked c60.png) — no other image moved.

- [ ] **Step 5: VISUAL control — read `scenery/images/bsp.png`**

Confirm: LEFT panel shows the documented artifact (one pane uniformly on top of the other, visibly wrong on one side of the crossing line — the orange pane appearing in front of the blue even where it passes behind, or vice versa); RIGHT panel shows correct interleaving: each pane is in front on one side of the crossing and behind on the other, with the crossing line visually coherent. If both panels look identical, BSP did not fire — stop and debug the predicate. If the RIGHT panel shows seams/gaps along the split line, report for adjudication (may need eps tuning).

- [ ] **Step 6: Commit**

```bash
git add scenery-engine/src/bsp.rs scenery-engine/src/pipeline.rs scenery-engine/tests/bsp.rs \
  scenery/plugin/scenery_engine.wasm scenery/tests/test-engine.typ \
  scenery/examples/bsp.typ scenery/images/bsp.png
git commit -m "feat(scenery-engine): BSP splitting for intersecting translucent faces (#33)"
```

---

### Task 6: Rust auto bond detection + covalent-radii codegen + Typst-equivalence gate

**Files:**
- Modify: `tools/gen_elements.py` (emit `wyckoff-io/src/radii.rs`)
- Create + commit: `wyckoff-io/src/radii.rs` (generated)
- Create: `wyckoff-io/src/bonds.rs`, `wyckoff-io/tests/bonds.rs`
- Modify: `wyckoff-io/src/lib.rs` (`detect_bonds` wasm func; xyz molecule path fills `bonds`), `wyckoff-io/src/xyz.rs`
- Modify: `wyckoff/src/io.typ` (pass `record.bonds` through), `wyckoff/src/structure.typ` (molecule `bonds:`), `wyckoff/src/figure.typ` (consume precomputed bonds)
- Create: `wyckoff/tests/test-bonds.typ`
- Modify (if needed): `wyckoff/tests/test-import-xyz.typ` (bonds no longer `none` for molecules)
- Rebuild + commit: `wyckoff/plugin/wyckoff_io.wasm`

**Interfaces:**
- Produces (Python → Rust, codegen): `tools/gen_elements.py` additionally writes `wyckoff-io/src/radii.rs` from the SAME `data` dict that produces `elements.json` — the values are the already-rounded `r-cov` floats, so the Rust and Typst rules **cannot drift** (any radii change regenerates both in one `make -C wyckoff data`):
  ```python
  RS = Path(__file__).resolve().parent.parent / "wyckoff-io" / "src" / "radii.rs"
  lines = [
      "// GENERATED by tools/gen_elements.py (run: make -C wyckoff data) -- DO NOT EDIT.",
      "// Covalent radii, IDENTICAL to wyckoff/data/elements.json's r-cov values",
      "// (same pymatgen source, same rounding) so the Rust and Typst bond rules",
      "// can never drift (M4 design doc, \"Data changes\").",
      "",
      "/// (element symbol, covalent radius in Angstrom), sorted by symbol.",
      "pub static R_COV: &[(&str, f64)] = &[",
  ]
  for sym in sorted(data):
      lines.append(f'    ("{sym}", {data[sym]["r-cov"]!r}),')
  lines += ["];", "", "/// Binary-search lookup.",
            "pub fn r_cov(symbol: &str) -> Option<f64> {",
            "    R_COV.binary_search_by(|(s, _)| (*s).cmp(symbol)).ok().map(|k| R_COV[k].1)",
            "}", ""]
  RS.write_text("\n".join(lines))
  print(f"wrote {RS} ({len(data)} radii)")
  ```
- Produces (Rust, `bonds.rs`): the **exact rule of `wyckoff/src/geometry.typ:85–111` (`find-bonds`, `rules == auto` branch)** — `0.4 Å ≤ d ≤ 1.15 × (r_cov(a) + r_cov(b))` — over a spatial hash:
  ```rust
  /// Spatial-hash auto bond detection. Mirrors wyckoff's Typst find-bonds
  /// (geometry.typ:85-111, auto rule): a pair bonds iff
  ///   d >= 0.4  &&  d <= 1.15 * (r_i + r_j),
  /// with d = sqrt(dx*dx + dy*dy + dz*dz) accumulated in x,y,z order (mirrors
  /// Typst vlen/vdot). Output is sorted ascending (i, j) with i < j — exactly
  /// the order the Typst double loop emits. Atoms whose element has no radius
  /// contribute no bonds (Typst would have rejected the element earlier).
  pub fn find_bonds(atoms: &[(String, [f64; 3])]) -> Vec<[usize; 2]>
  ```
  Implementation spec: `r_max` = max radius among the elements present (0 bonds if none); cell size `h = 1.15 * (2.0 * r_max)`; key `(floor(x/h), floor(y/h), floor(z/h))` as `(i64, i64, i64)` in a `HashMap<_, Vec<usize>>` filled in input order; for each atom `i` in input order, scan the 27 neighbor cells, test only `j > i` (each unordered pair is seen exactly once since `j` lives in exactly one cell); collect and finally `bonds.sort()` (lexicographic `[i, j]` — matches Typst's `i`-outer/`j`-inner ascending emission). **Never iterate the HashMap** (determinism).
- Produces (Rust, `lib.rs`): `detect_bonds(input: &[u8]) -> Result<Vec<u8>, String>` — JSON in (`[{"element": "Na", "cart": [x,y,z]}, ...]`), JSON out (`[[i,j], ...]`); and the xyz **molecule** parse path fills `record.bonds = Some(find_bonds(..))` (extended-xyz/periodic records keep `bonds: null` — the supercell caveat).
- Produces (Typst): `structure(.., bonds: none)` — accepted **only** in molecule mode (assert otherwise), validated (`(i, j)` int pairs, `0 ≤ i < j < atoms.len()`), stored on the molecule dict as `bonds:`; `io.typ` `record-to-structure` molecule branch becomes `structure(atoms: .., bonds: record.bonds)`; `figure.typ` `build-scene` bond selection (line 92) becomes:
  ```typ
  let pre = structure.at("bonds", default: none)
  let blist = if mode == "space-filling" or bonds == none { () }
    else if bonds == auto and pre != none { pre.map(b => (i: b.at(0), j: b.at(1))) }
    else { find-bonds(shown, bonds) }
  ```
  (Safe because molecule-mode `display-atoms` emits exactly `structure.atoms` in order — no supercell loop images for `periodic: (false, false, false)`; a user `bonds:` rules array still overrides via `find-bonds`.)
- Consumes: `radii.rs` (generated), existing `_io` plugin handle (`io.typ:8`).

- [ ] **Step 1: Failing Rust tests**

`wyckoff-io/tests/bonds.rs`:
1. **Water:** the exact coordinates of `wyckoff/examples/data/water.xyz` → bonds `[[0,1],[0,2]]` (O–H only; H–H at ~1.51 Å exceeds 1.15×(0.31+0.31)).
2. **Benzene (exact trigonometry, the Stage-3 fixture logic):** C hexagon radius 1.39, H radially at 2.48 → exactly 12 bonds (6 C–C ring + 6 C–H), no second-neighbor C–C (2.41 > 1.68), sorted (i, j).
3. **0.4 Å floor:** two H at 0.35 Å → no bond; at 0.45 Å → bond (both boundaries of the rule).
4. **Property check vs brute force:** a deterministic 200-atom pseudo-random cloud (fixed LCG seed written inline — no `rand` dep) → spatial-hash result equals the O(N²) double-loop reference implementing the same rule (guards the hash against cell-boundary bugs).
5. **Radii drift gate:** parse `../wyckoff/data/elements.json` (std fs — native tests only, `#[cfg(not(target_arch = "wasm32"))]`) and assert every entry's `r-cov` equals `radii::r_cov(sym)` exactly, and the counts match.
6. **detect_bonds JSON round-trip:** water atoms as JSON bytes → `[[0,1],[0,2]]`.
7. **xyz record fill:** parsing water.xyz content yields `record.bonds == Some(vec![[0,1],[0,2]])`; parsing an extended-xyz (periodic) fixture yields `bonds == None` (the supercell caveat, asserted).

Run: `cargo test --manifest-path wyckoff-io/Cargo.toml` — Expected: FAIL (no `radii`/`bonds` modules).

- [ ] **Step 2: Codegen + implementation**

Extend `tools/gen_elements.py` per the Interfaces block; run `make -C wyckoff data`. Expected output ends `wrote .../wyckoff-io/src/radii.rs (96 radii)`; `git status --short` shows ONLY `tools/gen_elements.py` + `wyckoff-io/src/radii.rs` (+ possibly nothing else — `elements.json` must NOT change: the codegen reads the same dict; if elements.json moved, STOP, the pipeline drifted). Implement `bonds.rs`, add `pub mod radii; pub mod bonds;` to `lib.rs`, add `detect_bonds`, fill `record.bonds` in the xyz molecule path. Make the Rust tests pass.

- [ ] **Step 3: Failing Typst equivalence test**

Create `wyckoff/tests/test-bonds.typ`:

```typ
#import "/src/io.typ": _io, import-xyz
#import "/src/geometry.typ": find-bonds, display-atoms
#import "/src/structure.typ": structure
#import "/src/figure.typ": build-scene

// ===== Rust/Typst bond-equivalence gate (design doc, "Testing & gates") =====
// Same rule, same radii source: the two implementations must agree exactly.

// 1. Imported molecule: the parser-precomputed bonds equal Typst find-bonds.
#let water = import-xyz("/examples/data/water.xyz")
#assert.eq(water.bonds, ((0, 1), (0, 2)))
#let shown = display-atoms(water)
#assert.eq(water.bonds.map(b => (i: b.at(0), j: b.at(1))), find-bonds(shown, auto))

// 2. detect_bonds on a PERIODIC displayed set (boundary images included) —
// the render-time accelerator path must match Typst on the same atom list.
#let nacl = structure(spacegroup: 225, lattice: (a: 5.64),
  sites: ((element: "Na", wyckoff: "a"), (element: "Cl", wyckoff: "b")))
#let shown2 = display-atoms(nacl)
#let rust2 = json(_io.detect_bonds(json.encode(
  shown2.map(a => (element: a.element, cart: a.cart)))))
#assert.eq(rust2.map(b => (i: b.at(0), j: b.at(1))), find-bonds(shown2, auto))

// 3. Benzene count pin (12 bonds), through detect_bonds.
#let ring(el, r) = range(6).map(k =>
  (element: el, cart: (r * calc.cos(k * 60deg), r * calc.sin(k * 60deg), 0.0)))
#let rust3 = json(_io.detect_bonds(json.encode(ring("C", 1.39) + ring("H", 2.48))))
#assert.eq(rust3.len(), 12)

// 4. The molecule figure is UNCHANGED by precomputed bonds: same prims as a
// hand-built structure without them (the bond sets are equal, so the scene is).
#let hand = structure(atoms: water.atoms.map(a => (a.element, a.cart)))
#assert.eq(build-scene(water).prims, build-scene(hand).prims)

Bonds OK
```

Run: `make pkgroot && TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff test` — Expected: FAIL (stale committed blob has no `detect_bonds`; and `water.bonds` doesn't exist on the structure).

- [ ] **Step 4: Typst wiring + blob rebuild**

Apply the `structure.typ` / `io.typ` / `figure.typ` edits per the Interfaces block. Rebuild + run:

```bash
make -C wyckoff plugin
TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff test
```

Expected: `All tests passed!`. If `test-import-xyz.typ` pinned `bonds` behavior that changed (molecule records now carry bonds), update that assert to the new expected value — the ONLY permissible change there.

- [ ] **Step 5: Zero-diff pixel control**

```bash
TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff images && git status --short wyckoff/images
```

Expected: **no output** — precomputed bonds equal Typst-found bonds (gate 4 above), so every molecule example (import-xyz, molecule-water, render-modes…) renders byte-identically.

- [ ] **Step 6: Commit**

```bash
git add tools/gen_elements.py wyckoff-io/src/radii.rs wyckoff-io/src/bonds.rs \
  wyckoff-io/src/lib.rs wyckoff-io/src/xyz.rs wyckoff-io/tests/bonds.rs \
  wyckoff/plugin/wyckoff_io.wasm wyckoff/src/io.typ wyckoff/src/structure.typ \
  wyckoff/src/figure.typ wyckoff/tests/test-bonds.typ
# plus wyckoff/tests/test-import-xyz.typ if its bonds assert was updated
git commit -m "feat(wyckoff-io): spatial-hash auto bond detection + radii codegen + equivalence gate"
```

---

### Task 7: wyckoff opt-in — `crystal()`/`molecule()` engine flag, cull mirror, render-time `detect_bonds`

**Files:**
- Create: `scenery-engine/src/cull.rs`, `scenery-engine/tests/cull.rs`
- Modify: `scenery-engine/src/pipeline.rs` (cull first)
- Modify: `wyckoff/src/figure.typ` (`build-scene`, `render`, `draw-scene`), `wyckoff/src/crystal.typ` (all three entry points)
- Create: `wyckoff/tests/equiv/equiv-figure.typ`; modify `wyckoff/Makefile` (`test-equiv`)
- Modify: `wyckoff/tests/test-bonds.typ` (engine bond parity), `wyckoff/README.md`
- Rebuild + commit: `scenery/plugin/scenery_engine.wasm`

**Interfaces:**
- Produces (Rust, `cull.rs`): the **exact mirror of wyckoff `occlude` (`figure.typ:213–244`)**, parameterized by the schema's `Cull` constants so the engine stays host-agnostic (policy crosses as numbers, not code):
  - projected spheres: `(c: (sx, sy), r: r * scale_at(depth), depth)`; projected segs: midpoint depth `d`, endpoints 2D, `w * scale_at(d)`;
  - **seg dropped** iff ∃ sphere: both endpoints strictly inside the disk (`dist² < r²`) AND `sd < sp.depth + seg_r_slack * sp.r`;
  - **edge dropped** iff both projected endpoints are `covered`: covered(q, ed) = ∃ sphere (`in-disk` AND `ed < sp.depth + point_r_slack * sp.r`) OR ∃ seg (`dist2_point_seg(q, a, b) < (seg_w_frac * w)²` AND `ed < b.depth + seg_d_slack`), with `dist2_point_seg` mirroring `figure.typ:187–198` (the clamped-`t` projection);
  - ALL spheres and ALL segs act as occluders (including segs that are themselves dropped — mirror of the pure path building its lists before filtering); survivors keep input order. Runs FIRST in the pipeline (the pure path runs `occlude` before `scene-group`); spheres/faces always survive, so the subsequent clip sees the same occluders either way.
- Produces (Typst, `figure.typ`):
  - `build-scene(.., engine: "typst")`: when `engine == "wasm"` and `bonds == auto` and no precomputed bonds, the bond list comes from `json(_io.detect_bonds(json.encode(shown.map(a => (element: a.element, cart: a.cart))))).map(b => (i: b.at(0), j: b.at(1)))` instead of `find-bonds(shown, auto)` (requires `#import "io.typ": _io` — note: `io.typ` already imports nothing from `figure.typ`, so no cycle). Everything downstream (two-tone split, trims, polyhedra from `blist`) is unchanged.
  - a module constant `#let _wy-cull = (seg-r-slack: 2.0, point-r-slack: 1.0, seg-w-frac: 0.45, seg-d-slack: 1.0)` — the verbatim `occlude` slacks;
  - `render(scene, width:, legend:, axes-info:, engine: "typst")` and `draw-scene(scene, scale:, engine: "typst")`: on `"wasm"` they skip Typst `occlude` and pass ALL prims plus `engine: "wasm", engine-cull: _wy-cull` to `scenery.scene-group`; on `"typst"` the body is verbatim today's.
- Produces (Typst, `crystal.typ`): `crystal(..)`, `crystal-group(..)`, `molecule(..)` gain `engine: "typst"`, forwarded to both `build-scene` (bond path) and `render`/`draw-scene`.
- **Parity argument (why no in-Typst survivor-set assert):** Task 4's gates already prove clip+sort parity; the ONLY new surface is cull, and any wrongly culled/kept seg or edge changes pixels — so the wyckoff **pixel gate carries the cull parity burden**, alongside Rust unit tests pinning each slack's boundary.

- [ ] **Step 1: Failing Rust cull tests**

`scenery-engine/tests/cull.rs` (camera `cam0`, cull constants `2.0/1.0/0.45/1.0`):
1. a short seg fully inside a sphere's disk and behind it (`sd < depth + 2r`) → dropped; the same seg pushed in front beyond the slack → kept (boundary: `sd = depth + 2r` exactly → kept, mirroring the strict `<`);
2. an edge with both endpoints under sphere disks and not clearly behind → dropped; one endpoint uncovered → kept;
3. an edge covered by a seg stroke (`dist² < (0.45 w)²`, `ed < seg depth + 1.0`) → dropped;
4. survivors preserve input order; spheres/faces/labels always survive;
5. a dropped seg still occludes edges (the lists-before-filter mirror).

- [ ] **Step 2: Implement `cull.rs`; pipeline order cull → clip → bsp → sort; rebuild blob; Rust tests green**

- [ ] **Step 3: Failing Typst tests, then the wiring**

Append to `wyckoff/tests/test-bonds.typ`:

```typ
// engine="wasm" bond path: identical scene to the pure path (detect_bonds
// equivalence lifted to the figure level).
#assert.eq(build-scene(nacl, engine: "wasm").prims, build-scene(nacl).prims)
```

Create `wyckoff/tests/equiv/equiv-figure.typ`:

```typ
// wyckoff pixel-equivalence gate: crystal() and molecule() through both
// engines must render byte-identically (cull + clip + sort + bonds parity).
#import "/lib.typ": structure, crystal, molecule, prototypes
#let eng = sys.inputs.at("engine", default: "typst")
#set page(width: auto, height: auto, margin: 0.5cm)
#crystal(prototypes.rocksalt("Na", "Cl", a: 5.64), engine: eng, width: 6cm)
#let ring(el, r) = range(6).map(k =>
  (el, (r * calc.cos(k * 60deg), r * calc.sin(k * 60deg), 0.0)))
#molecule(structure(atoms: ring("C", 1.39) + ring("H", 2.48)), engine: eng, width: 6cm)
#crystal(prototypes.rocksalt("Na", "Cl", a: 5.64), supercell: (2, 2, 1), engine: eng,
  view: (azimuth: 25deg, elevation: 15deg, mode: "perspective", distance: 18), width: 6cm)
```

`wyckoff/Makefile`: add `test-equiv` to `.PHONY` and to the `test` recipe's tail (after the loop, before the echo), mirroring scenery's target with the two `--input` compiles + `cmp` on `tests/equiv-figure-{typst,wasm}.png`.

Run the suite → FAIL (`unexpected argument: engine`). Then implement the `figure.typ`/`crystal.typ` edits per the Interfaces block.

- [ ] **Step 4: Run + zero-diff control**

```bash
TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff test
TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff images && git status --short wyckoff/images
make test
```

Expected: all pass including the wyckoff `cmp` (pixel parity across engines — **fourth bit-identity checkpoint, same STOP rule**); zero image diffs (default path untouched); all packages green.

- [ ] **Step 5: README**

In `wyckoff/README.md`, after the perspective section, add:

```markdown
### Large scenes: the WASM accelerator

`crystal()`, `crystal-group()` and `molecule()` take `engine: "wasm"` to run
bond detection, projection, occlusion culling, depth sorting, and translucent
BSP splitting through the bundled `scenery-engine` WebAssembly plugin. The
default (`engine: "typst"`) is pure Typst and renders pixel-identically on
scenes without intersecting translucent faces; the accelerator is for large
structures (hundreds to thousands of atoms) and for correct layering of
interpenetrating translucent polyhedra.
```

- [ ] **Step 6: Commit**

```bash
git add scenery-engine/src/cull.rs scenery-engine/src/pipeline.rs scenery-engine/tests/cull.rs \
  scenery/plugin/scenery_engine.wasm wyckoff/src/figure.typ wyckoff/src/crystal.typ \
  wyckoff/tests/equiv/equiv-figure.typ wyckoff/tests/test-bonds.typ wyckoff/Makefile wyckoff/README.md
git commit -m "feat(wyckoff): engine=\"wasm\" opt-in with occlusion-cull mirror + detect_bonds path (#32)"
```

---

### Task 8: ~1000-atom benchmark fixture + timing + docs

**Files:**
- Modify: `tools/gen_fixtures.py` (benchmark xyz writer)
- Create + commit: `wyckoff/examples/data/nacl-1000.xyz`
- Create: `wyckoff/examples/benchmark.typ`; create + commit `wyckoff/images/benchmark.png`
- Modify: `wyckoff/README.md` (recorded timings)

**Interfaces:**
- Produces (Python): appended to `tools/gen_fixtures.py` (called from its `__main__` flow) —
  ```python
  def write_benchmark_xyz():
      """1000-atom NaCl block (5x5x5 conventional cells) as a molecule-mode .xyz
      benchmark fixture for the scenery-engine accelerator (issue #32)."""
      a = 5.64
      basis = [("Na", (0.0, 0.0, 0.0)), ("Na", (0.5, 0.5, 0.0)), ("Na", (0.5, 0.0, 0.5)),
               ("Na", (0.0, 0.5, 0.5)), ("Cl", (0.5, 0.0, 0.0)), ("Cl", (0.0, 0.5, 0.0)),
               ("Cl", (0.0, 0.0, 0.5)), ("Cl", (0.5, 0.5, 0.5))]
      lines = ["1000", "NaCl 5x5x5 conventional-cell block (generated benchmark fixture)"]
      for i in range(5):
          for j in range(5):
              for k in range(5):
                  for el, (x, y, z) in basis:
                      lines.append(f"{el} {(i + x) * a:.3f} {(j + y) * a:.3f} {(k + z) * a:.3f}")
      out = Path(__file__).resolve().parent.parent / "wyckoff" / "examples" / "data" / "nacl-1000.xyz"
      out.write_text("\n".join(lines) + "\n")
      print(f"wrote {out} (1000 atoms)")
  ```
  (Na–Cl nearest neighbor 2.82 Å < 1.15×(1.66+1.02)=3.08 → ~2700 six-coordinate bonds; Na–Na/Cl–Cl at 3.99 Å do not bond — a clean, predictable bond graph.)
- Produces (Typst): `wyckoff/examples/benchmark.typ` —
  ```typ
  #import "/lib.typ": import-xyz, molecule

  // ~1000-atom accelerator benchmark (issue #32). Default engine=wasm so
  // `make examples`/`make images` (and CI) stay fast; the pure-Typst reference
  // is compiled manually with --input engine=typst (see README, Large scenes).
  // Recorded timings (typst 0.14.2, <machine noted in README>):
  //   engine=wasm:  <FILL IN>    engine=typst: <FILL IN>
  #set page(width: auto, height: auto, margin: 0.6cm)
  #let eng = sys.inputs.at("engine", default: "wasm")
  #molecule(import-xyz("/examples/data/nacl-1000.xyz"), engine: eng,
    bond-color: luma(120), legend: true, width: 10cm)
  ```
  (`bond-color:` single-tone halves the seg count — ~2700 segs + 1000 spheres; the deliberate scale point is the geometry pipeline, not cetz stroke volume.)
- Acceptance (#32): the wasm compile completes within a **documented budget (target ≤ 120 s; record the actual)**; the pure-Typst time is recorded once for comparison (if it exceeds 15 minutes, kill it and record “> 15 min” — that IS the result).

- [ ] **Step 1: Generate the fixture**

```bash
make -C wyckoff fixtures
git status --short wyckoff tools
```

Expected: `wrote .../nacl-1000.xyz (1000 atoms)`; git shows ONLY `tools/gen_fixtures.py` + the new `wyckoff/examples/data/nacl-1000.xyz`. **Negative control:** no `wyckoff/tests/fixtures/*.json` may change (the existing ground-truth generation is deterministic and untouched).

- [ ] **Step 2: Time both paths**

```bash
time (TYPST_PACKAGE_PATH="$PWD/_pkgroot" typst compile --root wyckoff --input engine=wasm \
  wyckoff/examples/benchmark.typ wyckoff/examples/benchmark.pdf)
time (TYPST_PACKAGE_PATH="$PWD/_pkgroot" typst compile --root wyckoff --input engine=typst \
  wyckoff/examples/benchmark.typ wyckoff/examples/benchmark.pdf)
```

Record both wall times into the example's header comment and the README section below. If the WASM path exceeds the 120 s target, profile where the time goes before adjusting: if cetz drawing dominates (not the engine), switching the example to `mode: "space-filling"` (1000 spheres, zero segs) is the sanctioned fallback — note it in the commit message.

- [ ] **Step 3: Image + visual control**

```bash
TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff images
git status --short wyckoff/images
```

Expected: only the new `benchmark.png`. Read it: a dense 5×5×5 NaCl block — purple/green spheres in rock-salt arrangement, uniform gray bonds, legend right, no missing octants, no bond stubs floating outside the block, nearer atoms drawn over farther ones (a garbled depth order at this scale is instantly visible as speckle).

- [ ] **Step 4: Document + full suite**

Append to the wyckoff README "Large scenes" section (Task 7): a short "Benchmark" paragraph with the two recorded timings, the machine, and the command lines. Then:

```bash
make test
```

Expected: `All package test suites passed!`

- [ ] **Step 5: Commit**

```bash
git add tools/gen_fixtures.py wyckoff/examples/data/nacl-1000.xyz \
  wyckoff/examples/benchmark.typ wyckoff/images/benchmark.png wyckoff/README.md
git commit -m "feat(wyckoff): 1000-atom accelerator benchmark fixture + recorded timings (#32)"
```

---

## Self-Review

**Spec coverage:**
- **#32 deliverables:** Rust engine (primitives + camera in, depth-ordered primitives with depth keys out; Typst keeps all styling) → Tasks 1–3; opt-in path in scenery (Task 4) and wyckoff (Task 7) with pure Typst default+fallback; ~1000-atom benchmark with recorded both-path timings → Task 8. **#32 acceptance:** ordering-equivalence asserted programmatically where neither path splits (Task 2/3 gates — stronger than the issue asks: exact dict equality including depths); time budget documented (Task 8); negative control (disabling the accelerator = default path, proven byte-level by the zero-diff image controls and pixel-level by the two `test-equiv` gates that literally render both). ✓
- **#33 deliverables:** BSP split of intersecting translucent polygons before ordering, on the accelerator path, documented as the correctness mode → Tasks 5, 7 (README). **#33 acceptance:** the intersecting-panes scene correct under BSP with the plain painter's sort mis-ordering shown side-by-side (`scenery/examples/bsp.typ`, in `make images`); negative control: non-intersecting translucent faces produce the same result with and without BSP, enforced THREE ways (Rust `OutRec` equality, Typst `assert.eq` vs the pure pipeline, and the standing pixel gate scene 2). ✓
- **Design-doc items:** two-artifact workspace (Task 1); CBOR for the primitive stream with the JSON/CBOR split justified and the 0.14.2 API verified; host-agnostic contract (geometry + numeric policy in, geometry + depth keys out; scoped so the pure path never loads the blob); resequenced Rust bond detection with spatial hash, radii compiled from the same `make data` source, record `bonds` filled for molecules, supercell caveat enforced by scope (periodic records keep `bonds: null`; the render-time displayed-set loop gets its fast home via `detect_bonds` on the engine path) → Tasks 6–7; the accelerator-equivalence gate defined at three levels exactly as the design doc requires (ordering only where nothing splits; pixels where both paths render; BSP-only splits documented, not byte-asserted). ✓

**The hard problems, resolved concretely:**
- *Equivalence gate:* level (a) exact ordering on non-splitting scenes, level (b) byte-identical PNGs via `sys.inputs` double-compile + `cmp` (works because the engine feeds the SAME `_record`/draw loop), level (c) BSP structural asserts + reviewed example. The gate's feasibility rests on the bit-identity strategy: trig coefficients computed once in Typst, engine restricted to exactly-rounded ops, identical expression order, stable sorts both sides — with four explicit STOP checkpoints if reality disagrees.
- *Boundary:* exact request/response schema in Task 1; the only style-derived data crossing is per-face `opaque` and per-seg `w` (geometric facts), plus numeric cull slacks (policy as parameters); depth keys map back via `i`-indexed reassembly so output order IS draw order.
- *Determinism:* stable `total_cmp` sorts, input-order emission with specified fragment tie-breaks, deterministic BSP partner order (ascending original index) and piece order (negative side first), no HashMap iteration, no libm in the engine.
- *Perspective:* the engine mirrors `project`/`project-scale` including the unscaled-depth-key convention and the behind-camera error; perspective scenes appear in the ordering, fragment, and pixel gates.
- *Build/CI:* both crates built fresh + cargo-tested in CI, both Typst suites (with the folded-in `test-equiv` gates) run against the fresh builds; the cross-OS byte-repro caveat is preserved verbatim.

**Ordering:** workspace/scaffold (1) → sort mirror (2) → clip mirror (3) → opt-in + pixel gate (4) → BSP (5) are strictly sequential. Bonds (6) is independent of 2–5 (only needs the Task-1 workspace) and can run in parallel with them. wyckoff wiring (7) needs 4+6. Benchmark (8) needs 7. Each task is independently committable with explicit paths.

**Placeholder scan:** complete code ships for all mechanical parts (workspace + crate manifests, schema.rs, lib.rs, engine.typ, Makefile targets, CI steps, codegen block, fixture generator, examples, README text, all Typst tests). The algorithmic mirrors (clip.rs, bsp.rs, cull.rs, bonds.rs) ship as precise per-function specs with cited source lines, fidelity rules, and transcribed pinning tests — transcription is deliberate (the fidelity rule forbids "improving" the code), and the pins are the enforcement.

**Known risks / adjudication flags:**
- The bit-identical mirroring bet (STOP checkpoints in Tasks 2, 3, 4, 7). Most likely failure: an overlooked libm call or expression-order slip; the checkpoints localize it.
- `ciborium` on `wasm32-unknown-unknown` is expected clean (no_std-adjacent, no OS deps); if the blob bloats past ~300 KB, `wasm-opt -Oz` and feature trimming are the first levers.
- BSP is mutual-plane splitting with ordering delegated to the centroid sort, not a full BSP-tree traversal — meets both #33 acceptance criteria; flagged as a naming/approach call for the adjudicator.
- Engine-side cull mirroring wyckoff `occlude` is scope beyond the issue text but is what makes the 1000-atom budget honest; dropping it (fallback: keep `occlude` in Typst and accept a slower documented budget) is an adjudicator option that removes Task 7 Steps 1–2 without touching the rest.
- The benchmark budget (≤ 120 s wasm) is a target, not a hard gate; cetz draw volume, not the engine, is the plausible blower, with the space-filling fallback sanctioned in Task 8.
