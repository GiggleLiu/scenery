# M4 Stage 2 (Periodic Formats) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import POSCAR and CIF files into wyckoff figures. POSCAR flows through the existing explicit-periodic `structure()` path. CIF supports two symmetry sub-paths: an explicit op loop applied in Rust (returns explicit atoms), or a spacegroup identifier expanded through wyckoff's Typst tables via a new `expand-general` helper. Files with neither are rejected with an error naming the missing tags.

**Architecture:** Stage 1's pipeline is unchanged: file bytes → `wyckoff-io.wasm` (Rust parser) → normalized JSON record → Typst `record-to-structure` → existing `structure()`/`crystal()`. Stage 2 adds two Rust parsers (`poscar.rs`, `cif.rs`) sharing a new `geom.rs` module (cell-params→vectors, cart↔frac, wrapping), makes `Record.asym_unit` a real type, and adds one Typst symmetry helper (`expand-general` in `symmetry.typ`) plus dispatch in `io.typ`. Table crystallography stays in Typst; literal op arithmetic the file itself asserts happens in Rust. Bond detection stays in Typst this stage (Rust bond detection is Stage 4).

**Tech Stack:** Rust (stable) + `wasm-minimal-protocol` + `serde`/`serde_json`; Typst 0.14.2 `plugin()` + `json`; existing wyckoff spacegroup tables (`data.typ` / `symmetry.typ`); GNU Make; GitHub Actions (already builds the plugin — no CI change needed).

Implements issues #25 (POSCAR) and #26 (CIF). Design: `docs/plans/2026-07-12-file-import-molecular-rendering-design.md` (see "Format handling" and "Architecture: the Rust/Typst boundary").

## Global Constraints

- Rust target: `wasm32-unknown-unknown` (freestanding, **no WASI**); crate stays host-agnostic — zero Typst/CeTZ assumptions.
- Plugin functions are byte-in/byte-out; parse errors return `Result<Vec<u8>, String>` so they surface as Typst errors, **never panics** (no `unwrap` on user input).
- The prebuilt `.wasm` is committed under `wyckoff/plugin/`; **rebuild it (`make -C wyckoff plugin`) after any Rust change and commit it in the same commit.**
- Crate version stays `0.1.0` (`wyckoff/tests/test-plugin.typ` pins `"wyckoff-io 0.1.0"`).
- Coordinates are Ångström (Cartesian) / dimensionless fractional. Cell angles in CIF are degrees.
- Typst tests run from the **repo root**: `make pkgroot && TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff test`. All shell commands below are run from the repo root.
- Fixture files under `wyckoff/` are the single source of truth: Rust tests `include_str!` them, Typst tests `read()` them — the two suites can never drift.
- Normalized record JSON schema — **the contract every task targets** (Stage 2 change: `asym_unit` becomes a real array; `null` still decodes to Typst `none`):
  ```json
  {
    "lattice": null | [[f,f,f],[f,f,f],[f,f,f]],
    "atoms": [{"element": "Na", "cart": [f,f,f], "frac": [f,f,f] (omitted when unknown)}],
    "spacegroup": null | int,
    "asym_unit": null | [{"element": "Na", "frac": [f,f,f]}],
    "bonds": null,
    "meta": {"source_format": "xyz|extxyz|poscar|cif", "n_atoms": int}
  }
  ```
  `meta.n_atoms` is informational: the number of atom entries the parser emitted (`atoms.len()`, or `asym_unit.len()` for the CIF identifier path).
- **CIF dispatch contract:** op loop present → explicit `atoms`, `spacegroup: null`, `asym_unit: null`. No op loop but spacegroup identifier → empty `atoms`, `spacegroup: <n>`, `asym_unit: [...]`. Neither → `Err` naming the missing tags. Typst `record-to-structure` dispatches on `record.spacegroup != none`.

---

### Task 1: Shared `geom` module + real `asym_unit` record type

**Files:**
- Create: `wyckoff-io/src/geom.rs`
- Create: `wyckoff-io/tests/geom.rs`
- Create: `wyckoff-io/tests/record.rs`
- Modify: `wyckoff-io/src/record.rs` (`AsymAtom`, `asym_unit: Option<Vec<AsymAtom>>`)
- Modify: `wyckoff-io/src/xyz.rs` (use `geom::{cart_to_frac, read3}`; delete local copies)
- Modify: `wyckoff-io/src/lib.rs` (add `pub mod geom;`)
- Rebuild + commit: `wyckoff/plugin/wyckoff_io.wasm`

**Interfaces:**
- Produces (Rust `geom`):
  - `pub fn cell_to_vectors(a: f64, b: f64, c: f64, alpha: f64, beta: f64, gamma: f64) -> Result<[[f64;3];3], String>` — angles in **degrees**; convention identical to Typst `lattice-vectors` in `wyckoff/src/lattice.typ`.
  - `pub fn frac_to_cart(l: &[[f64;3];3], f: [f64;3]) -> [f64;3]`
  - `pub fn cart_to_frac(l: &[[f64;3];3], c: [f64;3]) -> Result<[f64;3], String>` (moved verbatim from `xyz.rs`)
  - `pub fn wrap01(x: f64) -> f64` — wraps into `[0,1)`, snapping `1−1e-9..1` to `0`.
  - `pub fn read3<'a>(it: &mut impl Iterator<Item=&'a str>, what: &str) -> Result<[f64;3], String>` (generalized from `xyz.rs`; `what` names the line for errors)
- Produces (Rust `record`): `pub struct AsymAtom { element: String, frac: [f64;3] }`; `Record.asym_unit: Option<Vec<AsymAtom>>` serializing as JSON array when `Some`, `null` when `None` (no `skip_serializing_if` — the Typst consumer relies on the key being present).
- Consumes: nothing new; `xyz.rs` behavior is unchanged (pure refactor).

- [ ] **Step 1: Write the failing geom tests**

Create `wyckoff-io/tests/geom.rs`:

```rust
use wyckoff_io::geom::{cart_to_frac, cell_to_vectors, frac_to_cart, wrap01};

fn close(a: f64, b: f64) -> bool {
    (a - b).abs() < 1e-9
}

#[test]
fn cubic_cell_is_diagonal() {
    let l = cell_to_vectors(4.0, 4.0, 4.0, 90.0, 90.0, 90.0).unwrap();
    for i in 0..3 {
        for j in 0..3 {
            assert!(close(l[i][j], if i == j { 4.0 } else { 0.0 }), "l[{}][{}] = {}", i, j, l[i][j]);
        }
    }
}

#[test]
fn hexagonal_cell_matches_typst_convention() {
    // Must match wyckoff/src/lattice.typ lattice-vectors: a along +x, b in xy.
    let l = cell_to_vectors(3.0, 3.0, 5.0, 90.0, 90.0, 120.0).unwrap();
    assert!(close(l[0][0], 3.0) && close(l[0][1], 0.0) && close(l[0][2], 0.0));
    assert!(close(l[1][0], -1.5) && close(l[1][1], 3.0 * 0.75f64.sqrt()) && close(l[1][2], 0.0)); // b·sin 120° = 3√3/2
    assert!(close(l[2][0], 0.0) && close(l[2][1], 0.0) && close(l[2][2], 5.0));
}

#[test]
fn frac_cart_round_trip_triclinic() {
    let l = cell_to_vectors(4.0, 5.0, 6.0, 80.0, 95.0, 110.0).unwrap();
    let f = [0.12, 0.34, 0.56];
    let f2 = cart_to_frac(&l, frac_to_cart(&l, f)).unwrap();
    for k in 0..3 {
        assert!(close(f[k], f2[k]), "component {}: {} != {}", k, f[k], f2[k]);
    }
}

#[test]
fn degenerate_cells_are_rejected() {
    assert!(cell_to_vectors(0.0, 4.0, 4.0, 90.0, 90.0, 90.0).is_err()); // zero length
    assert!(cell_to_vectors(4.0, 4.0, 4.0, 90.0, 90.0, 180.0).is_err()); // gamma = 180
    assert!(cell_to_vectors(4.0, 4.0, 4.0, 10.0, 170.0, 90.0).is_err()); // impossible angles
}

#[test]
fn wrap01_wraps_and_snaps() {
    assert_eq!(wrap01(0.25), 0.25);
    assert_eq!(wrap01(1.0), 0.0);
    assert_eq!(wrap01(-0.25), 0.75);
    assert_eq!(wrap01(2.75), 0.75);
    assert_eq!(wrap01(1.0 - 1e-12), 0.0); // snap: op images at 0.999999999999 are 0
}
```

Create `wyckoff-io/tests/record.rs`:

```rust
use wyckoff_io::record::{Atom, AsymAtom, Meta, Record};

#[test]
fn asym_unit_serializes_as_array_when_present() {
    let rec = Record {
        lattice: Some([[5.64, 0.0, 0.0], [0.0, 5.64, 0.0], [0.0, 0.0, 5.64]]),
        atoms: vec![],
        spacegroup: Some(225),
        asym_unit: Some(vec![AsymAtom { element: "Na".into(), frac: [0.0, 0.0, 0.0] }]),
        bonds: None,
        meta: Meta { source_format: "cif".into(), n_atoms: 1 },
    };
    let v = serde_json::to_value(&rec).unwrap();
    assert_eq!(v["spacegroup"], 225);
    assert_eq!(v["asym_unit"][0]["element"], "Na");
    assert_eq!(v["asym_unit"][0]["frac"][2], 0.0);
}

#[test]
fn asym_unit_serializes_as_null_when_absent() {
    let rec = Record {
        lattice: None,
        atoms: vec![Atom { element: "O".into(), cart: [0.0; 3], frac: None }],
        spacegroup: None,
        asym_unit: None,
        bonds: None,
        meta: Meta { source_format: "xyz".into(), n_atoms: 1 },
    };
    let v = serde_json::to_value(&rec).unwrap();
    assert!(v["asym_unit"].is_null(), "asym_unit key must be present and null");
    assert!(v["spacegroup"].is_null());
    assert!(v["atoms"][0].get("frac").is_none(), "frac stays omitted for molecules");
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cargo test --manifest-path wyckoff-io/Cargo.toml`
Expected: FAIL — `unresolved import wyckoff_io::geom` and `no AsymAtom in record`.

- [ ] **Step 3: Implement `geom.rs`**

Create `wyckoff-io/src/geom.rs`:

```rust
//! Shared numeric helpers for the periodic-format parsers: cell-parameter ->
//! lattice-vector construction, cart<->frac conversion, fractional wrapping,
//! and a 3-float token reader. Lattice rows are the cell vectors a, b, c.

/// Build lattice vectors (rows) from cell parameters; angles in degrees.
/// Convention (must match wyckoff's Typst `lattice-vectors`): a along +x,
/// b in the xy-plane, c general:
///   v1 = (a, 0, 0)
///   v2 = (b·cos γ, b·sin γ, 0)
///   v3 = (c·cos β, c·(cos α − cos β·cos γ)/sin γ, sqrt(c² − v3x² − v3y²))
pub fn cell_to_vectors(a: f64, b: f64, c: f64, alpha: f64, beta: f64, gamma: f64) -> Result<[[f64; 3]; 3], String> {
    for (name, v) in [("a", a), ("b", b), ("c", c)] {
        if !(v.is_finite() && v > 0.0) {
            return Err(format!("cell length {} must be positive, got {}", name, v));
        }
    }
    let (ca, cb, cg) = (alpha.to_radians().cos(), beta.to_radians().cos(), gamma.to_radians().cos());
    let sg = gamma.to_radians().sin();
    if sg.abs() < 1e-9 {
        return Err("cell angle gamma must not be 0 or 180 degrees".into());
    }
    let cx = c * cb;
    let cy = c * (ca - cb * cg) / sg;
    let cz2 = c * c - cx * cx - cy * cy;
    if cz2 <= 0.0 {
        return Err(format!("cell angles ({}, {}, {}) are geometrically impossible", alpha, beta, gamma));
    }
    Ok([[a, 0.0, 0.0], [b * cg, b * sg, 0.0], [cx, cy, cz2.sqrt()]])
}

/// cart = fracᵀ · L, where lattice rows are the cell vectors.
pub fn frac_to_cart(l: &[[f64; 3]; 3], f: [f64; 3]) -> [f64; 3] {
    [0, 1, 2].map(|j| f[0] * l[0][j] + f[1] * l[1][j] + f[2] * l[2][j])
}

/// frac = L⁻¹ · cart (adjugate inverse, verified in Stage 1).
pub fn cart_to_frac(l: &[[f64; 3]; 3], c: [f64; 3]) -> Result<[f64; 3], String> {
    // Columns of M are the lattice vectors; solve M · frac = cart.
    let m = [
        [l[0][0], l[1][0], l[2][0]],
        [l[0][1], l[1][1], l[2][1]],
        [l[0][2], l[1][2], l[2][2]],
    ];
    let det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
        - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
        + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
    if det.abs() < 1e-12 {
        return Err("degenerate lattice (zero volume)".into());
    }
    let cof = [
        [ m[1][1]*m[2][2]-m[1][2]*m[2][1], -(m[1][0]*m[2][2]-m[1][2]*m[2][0]),  m[1][0]*m[2][1]-m[1][1]*m[2][0]],
        [-(m[0][1]*m[2][2]-m[0][2]*m[2][1]), m[0][0]*m[2][2]-m[0][2]*m[2][0], -(m[0][0]*m[2][1]-m[0][1]*m[2][0])],
        [ m[0][1]*m[1][2]-m[0][2]*m[1][1], -(m[0][0]*m[1][2]-m[0][2]*m[1][0]),  m[0][0]*m[1][1]-m[0][1]*m[1][0]],
    ];
    // inverse[i][j] = cof[j][i] / det
    let minv = [
        [cof[0][0]/det, cof[1][0]/det, cof[2][0]/det],
        [cof[0][1]/det, cof[1][1]/det, cof[2][1]/det],
        [cof[0][2]/det, cof[1][2]/det, cof[2][2]/det],
    ];
    Ok([
        minv[0][0]*c[0]+minv[0][1]*c[1]+minv[0][2]*c[2],
        minv[1][0]*c[0]+minv[1][1]*c[1]+minv[1][2]*c[2],
        minv[2][0]*c[0]+minv[2][1]*c[1]+minv[2][2]*c[2],
    ])
}

/// Wrap a fractional coordinate into [0, 1); snaps values within 1e-9 of 1 to 0
/// so symmetry-op images like 0.9999999999 deduplicate against 0.
pub fn wrap01(x: f64) -> f64 {
    let y = x.rem_euclid(1.0);
    if y > 1.0 - 1e-9 { 0.0 } else { y }
}

/// Read three finite floats from a whitespace token stream; `what` names the
/// line for error messages (e.g. "atom line 3", "lattice vector 2").
pub fn read3<'a>(it: &mut impl Iterator<Item = &'a str>, what: &str) -> Result<[f64; 3], String> {
    let mut v = [0.0f64; 3];
    for k in 0..3 {
        let tok = it.next().ok_or(format!("{} needs 3 numeric components", what))?;
        let x: f64 = tok.parse().map_err(|_| format!("bad number '{}' in {}", tok, what))?;
        if !x.is_finite() {
            return Err(format!("non-finite number '{}' in {}", tok, what));
        }
        v[k] = x;
    }
    Ok(v)
}
```

- [ ] **Step 4: Update `record.rs`**

Replace `wyckoff-io/src/record.rs` in full:

```rust
use serde::Serialize;

#[derive(Serialize, Debug, PartialEq)]
pub struct Atom {
    pub element: String,
    pub cart: [f64; 3],
    #[serde(skip_serializing_if = "Option::is_none")]
    pub frac: Option<[f64; 3]>,
}

/// One asymmetric-unit atom, fractional coordinates. Returned only by the CIF
/// spacegroup-identifier path; wyckoff's Typst tables expand it.
#[derive(Serialize, Debug, PartialEq, Clone)]
pub struct AsymAtom {
    pub element: String,
    pub frac: [f64; 3],
}

#[derive(Serialize, Debug, PartialEq)]
pub struct Meta {
    pub source_format: String,
    pub n_atoms: usize,
}

#[derive(Serialize, Debug, PartialEq)]
pub struct Record {
    pub lattice: Option<[[f64; 3]; 3]>,
    pub atoms: Vec<Atom>,
    pub spacegroup: Option<i64>,
    // Serializes as null when None (no skip): the Typst consumer relies on the
    // key existing and JSON null decoding to `none`.
    pub asym_unit: Option<Vec<AsymAtom>>,
    pub bonds: Option<Vec<[usize; 2]>>,
    pub meta: Meta,
}
```

- [ ] **Step 5: Refactor `xyz.rs` onto `geom`**

In `wyckoff-io/src/xyz.rs`:
1. Change the top import to `use crate::geom::{cart_to_frac, read3};` (keep `use crate::record::{Atom, Meta, Record};`).
2. Delete the local `fn read3` and `fn cart_to_frac` definitions entirely (keep `parse_lattice` — it is xyz-specific).
3. Change the `read3` call site to `let cart = read3(&mut it, &format!("atom line {}", i))?;`.

In `wyckoff-io/src/lib.rs`, add `pub mod geom;` alongside the existing `pub mod record;` / `pub mod xyz;`.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cargo test --manifest-path wyckoff-io/Cargo.toml`
Expected: all pass — the 5 new geom tests, 2 new record tests, **and the 4 pre-existing xyz tests unchanged** (the negative control that the refactor didn't change parser behavior).

- [ ] **Step 7: Rebuild the plugin and re-run the Typst suite**

Run: `make -C wyckoff plugin && make pkgroot && TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff test`
Expected: plugin rebuilds; Typst suite ends `All tests passed!` (existing `test-import-xyz.typ` proves the JSON contract is byte-compatible for the xyz paths).

- [ ] **Step 8: Commit**

```bash
git add wyckoff-io/src/ wyckoff-io/tests/ wyckoff/plugin/wyckoff_io.wasm
git commit -m "refactor(wyckoff-io): shared geom module + real asym_unit record type (#25, #26)"
```

---

### Task 2: POSCAR parser + `parse_poscar` export (issue #25)

**Files:**
- Create: `wyckoff-io/src/poscar.rs`
- Create: `wyckoff-io/tests/poscar.rs`
- Create: `wyckoff/examples/data/cu.poscar` (Direct-mode fixture)
- Create: `wyckoff/examples/data/nacl-cart.poscar` (Cartesian-mode + scale fixture)
- Create: `wyckoff/tests/data/bad-vasp4.poscar` (negative fixture, no symbols line)
- Modify: `wyckoff-io/src/lib.rs` (`pub mod poscar;` + `parse_poscar` export)
- Rebuild + commit: `wyckoff/plugin/wyckoff_io.wasm`

**Interfaces:**
- Consumes: `geom::{cart_to_frac, frac_to_cart, read3}`, `record::{Atom, Meta, Record}` (Task 1).
- Produces (Rust): `pub fn poscar::parse(input: &str) -> Result<Record, String>` — always a periodic record: `lattice: Some(scale·vectors)`, every atom with both `cart` and `frac: Some(..)`, `spacegroup: None`, `asym_unit: None`, `source_format: "poscar"`.
- Produces (wasm): `parse_poscar(input: &[u8]) -> Result<Vec<u8>, String>` returning the record as JSON bytes.
- Format decisions (VASP 5 subset): positive `scale` only — negative (target-volume form) and zero are rejected; a numeric first token on the symbols line means VASP 4 → rejected with a message pointing at VASP 5; optional `Selective dynamics` line (first letter `S`/`s`) is skipped; mode letter `d`/`D` = Direct, `c`/`C`/`k`/`K` = Cartesian, anything else rejected; **Cartesian positions are also multiplied by `scale`** (VASP semantics); trailing per-atom `T`/`F` flags are ignored.

- [ ] **Step 1: Add the fixture files**

Create `wyckoff/examples/data/cu.poscar` (FCC Cu conventional cell, a = 3.615 Å, 4 atoms — frac (0,0,0), (0,½,½), (½,0,½), (½,½,0)):

```
Cu fcc conventional cell
1.0
   3.615  0.000  0.000
   0.000  3.615  0.000
   0.000  0.000  3.615
Cu
4
Direct
 0.0 0.0 0.0
 0.0 0.5 0.5
 0.5 0.0 0.5
 0.5 0.5 0.0
```

Create `wyckoff/examples/data/nacl-cart.poscar` (NaCl rock salt, a = 5.64 Å, 8 atoms; exercises scale ≠ 1 applied to both lattice and Cartesian positions):

```
NaCl rock salt, Cartesian coordinates with a scale factor
5.64
1.0 0.0 0.0
0.0 1.0 0.0
0.0 0.0 1.0
Na Cl
4 4
Cartesian
0.0 0.0 0.0
0.0 0.5 0.5
0.5 0.0 0.5
0.5 0.5 0.0
0.5 0.5 0.5
0.5 0.0 0.0
0.0 0.5 0.0
0.0 0.0 0.5
```

Create `wyckoff/tests/data/bad-vasp4.poscar`:

```
Si diamond without a symbols line (VASP 4 format)
1.0
5.43 0.0 0.0
0.0 5.43 0.0
0.0 0.0 5.43
2
Direct
0.0 0.0 0.0
0.25 0.25 0.25
```

- [ ] **Step 2: Write the failing parser tests**

Create `wyckoff-io/tests/poscar.rs`:

```rust
use wyckoff_io::poscar;

const CU_DIRECT: &str = include_str!("../../wyckoff/examples/data/cu.poscar");
const NACL_CART: &str = include_str!("../../wyckoff/examples/data/nacl-cart.poscar");
const BAD_VASP4: &str = include_str!("../../wyckoff/tests/data/bad-vasp4.poscar");

fn close3(a: [f64; 3], b: [f64; 3]) -> bool {
    a.iter().zip(&b).all(|(x, y)| (x - y).abs() < 1e-9)
}

#[test]
fn parses_direct_mode() {
    let r = poscar::parse(CU_DIRECT).unwrap();
    let lat = r.lattice.unwrap();
    assert!(close3(lat[0], [3.615, 0.0, 0.0]) && close3(lat[1], [0.0, 3.615, 0.0]));
    assert_eq!(r.atoms.len(), 4);
    assert!(r.atoms.iter().all(|a| a.element == "Cu"));
    assert!(close3(r.atoms[1].frac.unwrap(), [0.0, 0.5, 0.5]));
    assert!(close3(r.atoms[1].cart, [0.0, 3.615 * 0.5, 3.615 * 0.5]));
    assert!(r.spacegroup.is_none() && r.asym_unit.is_none() && r.bonds.is_none());
    assert_eq!(r.meta.source_format, "poscar");
    assert_eq!(r.meta.n_atoms, 4);
}

#[test]
fn parses_cartesian_mode_with_scale() {
    let r = poscar::parse(NACL_CART).unwrap();
    let lat = r.lattice.unwrap();
    assert!(close3(lat[0], [5.64, 0.0, 0.0]));
    assert_eq!(r.atoms.len(), 8);
    assert_eq!(r.atoms.iter().filter(|a| a.element == "Na").count(), 4);
    assert_eq!(r.atoms.iter().filter(|a| a.element == "Cl").count(), 4);
    // atom 4 is the first Cl at Cartesian input (0.5,0.5,0.5): scaled by 5.64
    assert_eq!(r.atoms[4].element, "Cl");
    assert!(close3(r.atoms[4].cart, [5.64 * 0.5, 5.64 * 0.5, 5.64 * 0.5]));
    assert!(close3(r.atoms[4].frac.unwrap(), [0.5, 0.5, 0.5]));
}

#[test]
fn selective_dynamics_and_flags_are_skipped() {
    let src = CU_DIRECT.replace("Direct", "Selective dynamics\nDirect");
    let src = src.replace(" 0.5 0.5 0.0", " 0.5 0.5 0.0 T T F");
    let r = poscar::parse(&src).unwrap();
    assert_eq!(r.atoms.len(), 4);
    assert!(close3(r.atoms[3].frac.unwrap(), [0.5, 0.5, 0.0]));
}

#[test]
fn vasp4_without_symbols_is_rejected() {
    let err = poscar::parse(BAD_VASP4).unwrap_err();
    assert!(err.contains("VASP 4") && err.contains("symbols"), "err was: {}", err);
}

#[test]
fn negative_scale_is_rejected() {
    let src = NACL_CART.replace("5.64\n", "-100.0\n");
    let err = poscar::parse(&src).unwrap_err();
    assert!(err.contains("positive"), "err was: {}", err);
}

#[test]
fn symbol_count_mismatch_is_rejected() {
    let src = NACL_CART.replace("4 4", "4");
    let err = poscar::parse(&src).unwrap_err();
    assert!(err.contains("2 element symbols but 1 counts"), "err was: {}", err);
}

#[test]
fn bad_mode_line_is_rejected() {
    let src = CU_DIRECT.replace("Direct", "Fractional");
    assert!(poscar::parse(&src).is_err());
}

#[test]
fn truncated_file_is_error_not_panic() {
    assert!(poscar::parse("comment\n1.0\n3.0 0 0\n").is_err());
    assert!(poscar::parse("").is_err());
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cargo test --manifest-path wyckoff-io/Cargo.toml`
Expected: FAIL — `unresolved import wyckoff_io::poscar`.

- [ ] **Step 4: Implement the parser**

Create `wyckoff-io/src/poscar.rs`:

```rust
use crate::geom::{cart_to_frac, frac_to_cart, read3};
use crate::record::{Atom, Meta, Record};

/// Parse a VASP 5 POSCAR/CONTCAR into a periodic normalized record.
/// Supported: positive scale, element-symbols line, optional Selective
/// dynamics, Direct or Cartesian coordinates (Cartesian is scaled too).
/// Rejected: negative/zero scale (target-volume form), VASP 4 files without
/// an element-symbols line.
pub fn parse(input: &str) -> Result<Record, String> {
    let mut it = input.lines();
    let _comment = it.next().ok_or("empty POSCAR")?;

    let scale_line = it.next().ok_or("POSCAR truncated: missing scale line")?;
    let scale: f64 = scale_line
        .trim()
        .parse()
        .map_err(|_| format!("POSCAR scale must be a number, got '{}'", scale_line.trim()))?;
    if !(scale.is_finite() && scale > 0.0) {
        return Err(format!(
            "POSCAR scale must be positive, got '{}' (the negative target-volume form is not supported)",
            scale_line.trim()
        ));
    }

    let mut lattice = [[0.0f64; 3]; 3];
    for k in 0..3 {
        let line = it.next().ok_or(format!("POSCAR truncated: missing lattice vector {}", k + 1))?;
        let mut toks = line.split_whitespace();
        lattice[k] = read3(&mut toks, &format!("lattice vector {}", k + 1))?;
        for x in lattice[k].iter_mut() {
            *x *= scale;
        }
    }

    let sym_line = it.next().ok_or("POSCAR truncated: missing element-symbols line")?;
    let symbols: Vec<&str> = sym_line.split_whitespace().collect();
    if symbols.is_empty() {
        return Err("POSCAR element-symbols line is empty".into());
    }
    if symbols[0].parse::<u64>().is_ok() {
        return Err("POSCAR has no element-symbols line (VASP 4 format); insert a VASP 5 \
                    symbols line (e.g. 'Na Cl') before the per-species counts line"
            .into());
    }

    let cnt_line = it.next().ok_or("POSCAR truncated: missing per-species counts line")?;
    let counts: Vec<usize> = cnt_line
        .split_whitespace()
        .map(|t| t.parse::<usize>().map_err(|_| format!("bad species count '{}'", t)))
        .collect::<Result<_, _>>()?;
    if counts.len() != symbols.len() {
        return Err(format!(
            "POSCAR has {} element symbols but {} counts",
            symbols.len(),
            counts.len()
        ));
    }
    let n: usize = counts.iter().sum();

    let mut mode_line = it.next().ok_or("POSCAR truncated: missing coordinate-mode line")?;
    if mode_line.trim_start().starts_with(['S', 's']) {
        // "Selective dynamics" — skip it and read the real mode line.
        mode_line = it
            .next()
            .ok_or("POSCAR truncated: missing coordinate-mode line after Selective dynamics")?;
    }
    let cartesian = match mode_line.trim_start().chars().next() {
        Some('d') | Some('D') => false,
        Some('c') | Some('C') | Some('k') | Some('K') => true,
        _ => {
            return Err(format!(
                "POSCAR coordinate mode must start with D(irect) or C(artesian)/K, got '{}'",
                mode_line.trim()
            ))
        }
    };

    let mut species: Vec<String> = Vec::with_capacity(n);
    for (s, &c) in symbols.iter().zip(&counts) {
        for _ in 0..c {
            species.push((*s).to_string());
        }
    }

    let mut atoms = Vec::with_capacity(n);
    for i in 0..n {
        let line = it
            .next()
            .ok_or(format!("POSCAR declares {} atoms but atom line {} is missing", n, i + 1))?;
        let mut toks = line.split_whitespace();
        let v = read3(&mut toks, &format!("atom line {}", i + 1))?; // trailing T/F flags ignored
        let (cart, frac) = if cartesian {
            let c = [v[0] * scale, v[1] * scale, v[2] * scale];
            let f = cart_to_frac(&lattice, c)?;
            (c, f)
        } else {
            (frac_to_cart(&lattice, v), v)
        };
        atoms.push(Atom { element: species[i].clone(), cart, frac: Some(frac) });
    }

    Ok(Record {
        lattice: Some(lattice),
        atoms,
        spacegroup: None,
        asym_unit: None,
        bonds: None,
        meta: Meta { source_format: "poscar".into(), n_atoms: n },
    })
}
```

- [ ] **Step 5: Wire the module + wasm export in `lib.rs`**

In `wyckoff-io/src/lib.rs`, add `pub mod poscar;` to the module list, and after `parse_xyz` add:

```rust
#[cfg_attr(target_arch = "wasm32", wasm_func)]
pub fn parse_poscar(input: &[u8]) -> Result<Vec<u8>, String> {
    let text = std::str::from_utf8(input).map_err(|e| e.to_string())?;
    let record = poscar::parse(text)?;
    serde_json::to_vec(&record).map_err(|e| e.to_string())
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cargo test --manifest-path wyckoff-io/Cargo.toml`
Expected: all pass, including the 8 new poscar tests (`parses_direct_mode`, `parses_cartesian_mode_with_scale`, `selective_dynamics_and_flags_are_skipped`, `vasp4_without_symbols_is_rejected`, `negative_scale_is_rejected`, `symbol_count_mismatch_is_rejected`, `bad_mode_line_is_rejected`, `truncated_file_is_error_not_panic`).

- [ ] **Step 7: Rebuild the plugin**

Run: `make -C wyckoff plugin`
Expected: rebuilds `wyckoff/plugin/wyckoff_io.wasm` (now exporting `parse_poscar`).

- [ ] **Step 8: Commit**

```bash
git add wyckoff-io/src/ wyckoff-io/tests/ wyckoff/examples/data/ wyckoff/tests/data/ wyckoff/plugin/wyckoff_io.wasm
git commit -m "feat(wyckoff-io): POSCAR parser to normalized record (#25)"
```

---

### Task 3: `import-poscar` end-to-end (issue #25)

**Files:**
- Modify: `wyckoff/src/io.typ` (add `import-poscar`)
- Modify: `wyckoff/lib.typ` (export `import-poscar`)
- Create: `wyckoff/tests/test-import-poscar.typ`
- Create: `wyckoff/examples/import-poscar.typ`
- Modify: `wyckoff/README.md` (document `import-poscar`)

**Interfaces:**
- Consumes: `_io.parse_poscar(bytes) -> bytes` (Task 2); the existing `record-to-structure` explicit-periodic branch (`lattice` present, `spacegroup == none` → `structure(lattice:, atoms: frac-pairs)`) — **no change to `record-to-structure` in this task**; fixtures from Task 2.
- Produces (Typst): `import-poscar(path) -> structure` (kind `"3d"`, periodic `(true, true, true)`).

- [ ] **Step 1: Write the failing import test**

Create `wyckoff/tests/test-import-poscar.typ`:

```typ
#import "/src/io.typ": import-poscar

// Direct-mode POSCAR -> periodic structure.
#let cu = import-poscar("/examples/data/cu.poscar")
#assert.eq(cu.kind, "3d")
#assert.eq(cu.periodic, (true, true, true))
#assert.eq(cu.vectors.at(0), (3.615, 0.0, 0.0))
#assert.eq(cu.atoms.len(), 4)
#assert(cu.atoms.all(a => a.element == "Cu"))
#assert.eq(cu.atoms.at(1).frac, (0.0, 0.5, 0.5))

// Cartesian-mode POSCAR with scale factor -> same NaCl cell as the fixtures.
#let nacl = import-poscar("/examples/data/nacl-cart.poscar")
#assert.eq(nacl.kind, "3d")
#assert.eq(nacl.atoms.len(), 8)
#assert.eq(nacl.atoms.filter(a => a.element == "Na").len(), 4)
#assert.eq(nacl.atoms.filter(a => a.element == "Cl").len(), 4)
#assert.eq(nacl.vectors.at(0), (5.64, 0.0, 0.0))
#let cl = nacl.atoms.at(4)
#assert.eq(cl.element, "Cl")
#assert(range(3).all(i => calc.abs(cl.frac.at(i) - 0.5) < 1e-9), message: "first Cl at (1/2,1/2,1/2)")
POSCAR import OK
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `make pkgroot && TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff test`
Expected: FAIL — `import-poscar` is not defined in `io.typ`.

- [ ] **Step 3: Implement `import-poscar`**

In `wyckoff/src/io.typ`, after `import-xyz`, add:

```typ
/// Read a VASP 5 POSCAR/CONTCAR file and return a periodic structure.
/// Direct and Cartesian coordinate modes are supported; the scale factor is
/// applied to the lattice (and, per VASP semantics, to Cartesian positions).
#let import-poscar(path) = {
  let raw = read(path, encoding: none)   // bytes
  let record = json(_io.parse_poscar(raw))
  record-to-structure(record)
}
```

In `wyckoff/lib.typ`, change the io import line to:

```typ
#import "src/io.typ": import-xyz, import-poscar
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff test`
Expected: `tests/test-import-poscar.typ` compiles; suite ends `All tests passed!`.

- [ ] **Step 5: Verify the negative control (VASP 4 file errors clearly)**

Run:

```bash
printf '#import "/lib.typ": import-poscar\n#let _ = import-poscar("/tests/data/bad-vasp4.poscar")\n' > wyckoff/tests/neg-vasp4.typ
(TYPST_PACKAGE_PATH="$PWD/_pkgroot" typst compile --root wyckoff wyckoff/tests/neg-vasp4.typ /tmp/neg-vasp4.pdf; echo "exit=$?")
rm wyckoff/tests/neg-vasp4.typ
```

Expected: compile FAILS with a plugin error containing `VASP 4` and `symbols line`, `exit=` nonzero — the Rust error surfaces verbatim in Typst, not a silent empty figure. (The temp file is named `neg-*.typ` so the `tests/test-*.typ` glob never picks it up.)

- [ ] **Step 6: Add a rendered example**

Create `wyckoff/examples/import-poscar.typ`:

```typ
#import "/lib.typ": import-poscar, crystal

// FCC copper straight from a Direct-mode POSCAR.
#crystal(import-poscar("/examples/data/cu.poscar"), width: 5cm)

// NaCl from a Cartesian-mode POSCAR with a scale factor.
#crystal(import-poscar("/examples/data/nacl-cart.poscar"), width: 5cm)
```

- [ ] **Step 7: Compile the example and render the image**

Run: `TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff examples && TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff images`
Expected: `examples/import-poscar.pdf` compiles; `images/import-poscar.png` shows the 4-atom Cu cell and the 8-atom NaCl cell, both with unit-cell boxes.

- [ ] **Step 8: Document `import-poscar` in the README**

In `wyckoff/README.md`, in the "Importing from files" subsection (after the `import-xyz` paragraph), add:

```markdown
`import-poscar(path)` reads a VASP 5 `POSCAR`/`CONTCAR` (element-symbols line
required; Direct or Cartesian coordinates; positive scale factor) and returns
a periodic structure.

    #import "@preview/wyckoff:0.1.0": import-poscar, crystal
    #crystal(import-poscar("POSCAR"))
```

(Keep the indented-code style shown above, matching the existing `import-xyz` snippet's fenced style — if the README uses ```` ```typst ```` fences there, use the same fence style for consistency.)

- [ ] **Step 9: Commit**

```bash
git add wyckoff/src/io.typ wyckoff/lib.typ wyckoff/tests/test-import-poscar.typ wyckoff/examples/import-poscar.typ wyckoff/images/import-poscar.png wyckoff/README.md
git commit -m "feat(wyckoff): import-poscar end-to-end (#25)"
```

---

### Task 4: CIF parser (both sub-path records) + `parse_cif` export (issue #26)

**Files:**
- Create: `wyckoff-io/src/cif.rs`
- Create: `wyckoff-io/src/sg_symbols.rs` (generated H-M → IT-number table, committed)
- Create: `wyckoff-io/tests/cif.rs`
- Create: `wyckoff/examples/data/nacl-ops.cif` (op-loop fixture)
- Create: `wyckoff/examples/data/nacl-sg.cif` (spacegroup-identifier fixture)
- Create: `wyckoff/tests/data/nacl-nosym.cif` (negative fixture)
- Modify: `wyckoff-io/src/lib.rs` (`pub mod cif; pub mod sg_symbols;` + `parse_cif` export)
- Rebuild + commit: `wyckoff/plugin/wyckoff_io.wasm`

**Interfaces:**
- Consumes: `geom::{cell_to_vectors, frac_to_cart, wrap01}`, `record::{AsymAtom, Atom, Meta, Record}`.
- Produces (Rust):
  - `pub fn cif::parse(input: &str) -> Result<Record, String>` — dispatch per the Global Constraints contract.
  - `pub struct cif::SymOp { pub rot: [[i32;3];3], pub trans: [f64;3] }` and `pub fn cif::parse_op(s: &str) -> Result<SymOp, String>` (public for tests).
  - `pub fn cif::element_symbol(token: &str) -> Result<String, String>` (public for tests).
  - `pub const sg_symbols::SG_SYMBOLS: &[(&str, i64)]` — 230 entries, normalized short H-M symbol → IT number.
- Produces (wasm): `parse_cif(input: &[u8]) -> Result<Vec<u8>, String>`.

**CIF subset specification (this is the contract the tests pin):**

*Tokenizer* (line-oriented pre-pass, then a token stream):
1. A line whose **first character** is `;` starts a multi-line text field; skip every line up to and including the next line starting with `;`. (Text fields are free prose we never need. If skipping one leaves a loop ragged, the malformed-loop error below fires.)
2. Within a line, tokens are whitespace-delimited, except quoted tokens: a token starting with `'` or `"` runs to the matching closing quote (quotes stripped; the quoted content may contain spaces and commas — symmetry ops rely on this).
3. An unquoted token starting with `#` ends that line's tokens (comment).
4. Keywords are case-insensitive: a token equal to `loop_` (case-insensitive) opens a loop; a token starting with `data_` (case-insensitive) is a block header. **More than one `data_` block → `Err("CIF has multiple data_ blocks; only single-block files are supported")`.**
5. Tags (tokens starting with `_`) are stored lowercased (CIF tags are case-insensitive; note `_symmetry_space_group_name_H-M` → `_symmetry_space_group_name_h-m`).
6. Stream grammar: `loop_` collects consecutive `_tag` tokens as columns, then value tokens until the next token starting with `_`, `loop_`, `data_`, or EOF; **the value count must be an exact multiple of the column count**, else `Err` containing `"malformed loop"` and the first column tag. A bare `_tag` outside a loop takes the single next token as its value (missing value → `Err`).
7. Result type: `struct Cif { scalars: HashMap<String, String>, loops: Vec<Loop> }`, `struct Loop { tags: Vec<String>, rows: Vec<Vec<String>> }`, plus `fn find_loop<'a>(cif: &'a Cif, tag: &str) -> Option<(&'a Loop, usize)>` returning the first loop containing `tag` and that tag's column index.

*Numeric values:* `fn num(v: &str) -> Result<f64, String>` strips a trailing standard-uncertainty suffix `(...)` (e.g. `5.6402(3)` → `5.6402`), then parses; `.` and `?` (CIF unknown/absent markers) are errors when the value is required.

*Cell:* all six of `_cell_length_a/b/c`, `_cell_angle_alpha/beta/gamma` are required; a missing one → `Err` naming that exact tag. Vectors via `geom::cell_to_vectors` (angles degrees).

*Atom sites:* the loop containing `_atom_site_fract_x` (also requires `_atom_site_fract_y`/`_atom_site_fract_z` in the same loop — missing → `Err` naming the tag). Element per row from `_atom_site_type_symbol` if that column exists, else `_atom_site_label`, else `Err`. `element_symbol(token)`: take the leading ASCII-alphabetic prefix (strips `1`, `2-`, `2+`, …), require length 1–2, uppercase the first letter and lowercase the rest (`"Na1"→"Na"`, `"O2-"→"O"`, `"NA"→"Na"`); anything else → `Err`. Fractional coordinates wrapped with `wrap01`. If an `_atom_site_occupancy` column exists and any value differs from 1.0 by more than 1e-3 → `Err` containing `"occupancy"` (partial occupancy/disorder is out of scope by design).

*Symmetry-op strings* (grammar; whitespace ignored, case-insensitive):

```
op-string   := component ',' component ',' component
component   := signed-term+              (first sign optional)
signed-term := ('+' | '-')? term
term        := 'x' | 'y' | 'z'           -> accumulate ±1 into rot[row][col]
             | INT '/' INT               -> rational constant into trans[row]
             | DECIMAL | INT             -> constant into trans[row]  (e.g. 0.5)
```

Each component yields one row of `rot` (i32 entries, accumulated so `x-y` gives `[1,-1,0]`) and one `trans` entry, wrapped with `wrap01` (so `x-1/4` → trans 0.75). Errors: not exactly 3 components, dangling sign, unknown character, division by zero. (Numeric coefficients on variables, e.g. `2x`, do not occur in crystallographic ops and are not supported.)

*Op application:* for each asym atom, for each op, `q[i] = wrap01(Σ_j rot[i][j]·frac[j] + trans[i])`; deduplicate per-atom-orbit with periodic min-image tolerance `1e-3` in fractional coordinates (file coordinates are low-precision; distinct atoms are far apart). Output order: asym atoms in file order, each followed by its orbit in op order.

*Dispatch:*
1. A loop containing `_symmetry_equiv_pos_as_xyz` **or** `_space_group_symop_operation_xyz` (id columns like `_symmetry_equiv_pos_site_id` may be present and are ignored) → parse all ops, apply, return explicit atoms (`cart` via `frac_to_cart`), `spacegroup: None`, `asym_unit: None`, `n_atoms = atoms.len()`.
2. Else `_space_group_it_number` or `_symmetry_int_tables_number` (integer, must be 1–230 else `Err`) → return `atoms: vec![]`, `spacegroup: Some(n)`, `asym_unit: Some(asym)`, `n_atoms = asym.len()`. Else `_symmetry_space_group_name_h-m`: normalize the value by removing whitespace, `_`, `'`, `"`; look up in `SG_SYMBOLS`; found → as above; not found → `Err` containing the symbol and advising `_space_group_IT_number`.
3. Neither → `Err` naming all the candidate tags: must contain `_symmetry_equiv_pos_as_xyz`, `_space_group_symop_operation_xyz`, `_space_group_IT_number`, and `_symmetry_space_group_name_H-M`.

- [ ] **Step 1: Generate the H-M symbol table**

Run from the repo root:

```bash
python3 - <<'EOF' > wyckoff-io/src/sg_symbols.rs
import json
d = json.load(open('wyckoff/data/spacegroups.json'))
print("// Generated from wyckoff/data/spacegroups.json - do not edit by hand.")
print("// Regenerate with the command in docs/superpowers/plans/2026-07-12-m4-stage2-periodic.md (Task 4).")
print("// Short Hermann-Mauguin symbol (whitespace/underscores stripped) -> IT number.")
print("pub const SG_SYMBOLS: &[(&str, i64)] = &[")
for n in range(1, 231):
    sym = d[str(n)]["symbol"].replace(" ", "").replace("_", "")
    print(f'    ("{sym}", {n}),')
print("];")
EOF
grep -c '("' wyckoff-io/src/sg_symbols.rs
```

Expected: the `grep -c` prints `230`. `head -6 wyckoff-io/src/sg_symbols.rs` shows the header comments, `pub const SG_SYMBOLS`, and `("P1", 1),`. (Symbols are unique after normalization — verified against the JSON; e.g. entry 225 is `("Fm-3m", 225)`.)

- [ ] **Step 2: Add the fixture files**

Create `wyckoff/examples/data/nacl-ops.cif`. **Fixture math (hand-verifiable):** NaCl, a = 5.64 Å, asym unit Na (0,0,0) + Cl (½,0,0). The 7 ops below are a minimal set that generates the full cell *from this asym unit* — Na orbit {(0,0,0),(0,½,½),(½,0,½),(½,½,0)}, Cl orbit {(½,0,0),(0,½,0),(0,0,½),(½,½,½)} — 8 atoms, exactly the NaCl conventional cell. They deliberately exercise the grammar: identity, cyclic permutations, inversion, and half-translations in both the `x+1/2` and `1/2+x` spellings.

```
data_nacl
# NaCl with an explicit symmetry-op loop, applied directly by wyckoff-io.
# Minimal op set that generates the full cell from THIS asymmetric unit;
# database exports typically list all 192 Fm-3m ops. The parser applies
# whatever the file asserts and deduplicates.
_cell_length_a 5.64
_cell_length_b 5.64
_cell_length_c 5.64
_cell_angle_alpha 90
_cell_angle_beta 90
_cell_angle_gamma 90
loop_
_symmetry_equiv_pos_as_xyz
'x, y, z'
'z, x, y'
'y, z, x'
'-x, -y, -z'
'x, y+1/2, z+1/2'
'1/2+x, y, 1/2+z'
'x+1/2, y+1/2, z'
loop_
_atom_site_label
_atom_site_fract_x
_atom_site_fract_y
_atom_site_fract_z
Na1 0.0 0.0 0.0
Cl1 0.5 0.0 0.0
```

Create `wyckoff/examples/data/nacl-sg.cif` — the **same structure**, identifier-only (this pair is the two-sub-paths-agree gate in Task 5):

```
data_nacl
# NaCl via a spacegroup identifier only (no op loop): wyckoff's Typst
# tables expand the asymmetric unit.
_space_group_IT_number 225
_cell_length_a 5.64
_cell_length_b 5.64
_cell_length_c 5.64
_cell_angle_alpha 90
_cell_angle_beta 90
_cell_angle_gamma 90
loop_
_atom_site_type_symbol
_atom_site_fract_x
_atom_site_fract_y
_atom_site_fract_z
Na 0.0 0.0 0.0
Cl 0.5 0.0 0.0
```

Create `wyckoff/tests/data/nacl-nosym.cif` (negative: neither op loop nor identifier):

```
data_nacl
_cell_length_a 5.64
_cell_length_b 5.64
_cell_length_c 5.64
_cell_angle_alpha 90
_cell_angle_beta 90
_cell_angle_gamma 90
loop_
_atom_site_type_symbol
_atom_site_fract_x
_atom_site_fract_y
_atom_site_fract_z
Na 0.0 0.0 0.0
Cl 0.5 0.0 0.0
```

- [ ] **Step 3: Write the failing tests (this battery pins the whole spec)**

Create `wyckoff-io/tests/cif.rs`:

```rust
use wyckoff_io::cif::{self, element_symbol, parse_op};

const NACL_OPS: &str = include_str!("../../wyckoff/examples/data/nacl-ops.cif");
const NACL_SG: &str = include_str!("../../wyckoff/examples/data/nacl-sg.cif");
const NACL_NOSYM: &str = include_str!("../../wyckoff/tests/data/nacl-nosym.cif");

fn close(a: f64, b: f64) -> bool {
    (a - b).abs() < 1e-9
}
// Periodic min-image comparison for fractional coordinates.
fn close3f(a: [f64; 3], b: [f64; 3]) -> bool {
    a.iter().zip(&b).all(|(x, y)| {
        let d = (x - y).abs();
        d.min((d - 1.0).abs()) < 1e-6
    })
}

// ---- op-string grammar ----

#[test]
fn op_identity() {
    let op = parse_op("x, y, z").unwrap();
    assert_eq!(op.rot, [[1, 0, 0], [0, 1, 0], [0, 0, 1]]);
    assert_eq!(op.trans, [0.0, 0.0, 0.0]);
}

#[test]
fn op_inversion() {
    let op = parse_op("-x,-y,-z").unwrap();
    assert_eq!(op.rot, [[-1, 0, 0], [0, -1, 0], [0, 0, -1]]);
}

#[test]
fn op_translation_both_spellings_agree() {
    let a = parse_op("x, y+1/2, z+1/2").unwrap();
    let b = parse_op("+x, 1/2+y, 1/2+z").unwrap();
    assert_eq!(a.rot, b.rot);
    assert!(a.trans.iter().zip(&b.trans).all(|(p, q)| close(*p, *q)));
    assert!(close(a.trans[1], 0.5) && close(a.trans[2], 0.5));
}

#[test]
fn op_hexagonal_two_var_component() {
    let op = parse_op("-y+1/2, x-y, z").unwrap();
    assert_eq!(op.rot, [[0, -1, 0], [1, -1, 0], [0, 0, 1]]);
    assert!(close(op.trans[0], 0.5) && close(op.trans[1], 0.0) && close(op.trans[2], 0.0));
}

#[test]
fn op_decimal_translation_and_case_insensitive() {
    let op = parse_op("0.5-X, Y, Z").unwrap();
    assert_eq!(op.rot[0], [-1, 0, 0]);
    assert!(close(op.trans[0], 0.5));
}

#[test]
fn op_negative_translation_wraps() {
    let op = parse_op("x-1/4, y, z").unwrap();
    assert!(close(op.trans[0], 0.75));
}

#[test]
fn op_malformed_is_error() {
    assert!(parse_op("x, y").is_err()); // 2 components
    assert!(parse_op("x, y, z, x").is_err()); // 4 components
    assert!(parse_op("x, q, z").is_err()); // unknown variable
    assert!(parse_op("x, y, 1/0").is_err()); // division by zero
    assert!(parse_op("x, y, +").is_err()); // dangling sign
}

// ---- element normalization ----

#[test]
fn element_symbols_normalize() {
    assert_eq!(element_symbol("Na1").unwrap(), "Na");
    assert_eq!(element_symbol("O2-").unwrap(), "O");
    assert_eq!(element_symbol("NA").unwrap(), "Na");
    assert_eq!(element_symbol("Ca2+").unwrap(), "Ca");
    assert!(element_symbol("123").is_err());
    assert!(element_symbol("Wat1").is_err()); // 3-letter prefix: not an element
}

// ---- sub-path 1: explicit op loop ----

#[test]
fn op_loop_cif_expands_to_full_cell() {
    let r = cif::parse(NACL_OPS).unwrap();
    let lat = r.lattice.unwrap();
    assert!(close(lat[0][0], 5.64) && close(lat[1][1], 5.64) && close(lat[2][2], 5.64));
    assert_eq!(r.atoms.len(), 8);
    assert!(r.spacegroup.is_none(), "op-loop path returns explicit atoms, no spacegroup");
    assert!(r.asym_unit.is_none());
    assert_eq!(r.atoms.iter().filter(|a| a.element == "Na").count(), 4);
    assert_eq!(r.atoms.iter().filter(|a| a.element == "Cl").count(), 4);
    let has = |el: &str, f: [f64; 3]| r.atoms.iter().any(|a| a.element == el && close3f(a.frac.unwrap(), f));
    assert!(has("Na", [0.0, 0.0, 0.0]));
    assert!(has("Na", [0.0, 0.5, 0.5]));
    assert!(has("Cl", [0.5, 0.5, 0.5]));
    assert!(has("Cl", [0.0, 0.0, 0.5]));
    // cart of Cl (1/2,1/2,1/2) in the a=5.64 cubic cell
    let cl = r.atoms.iter().find(|a| a.element == "Cl" && close3f(a.frac.unwrap(), [0.5, 0.5, 0.5])).unwrap();
    assert!(cl.cart.iter().all(|&x| (x - 2.82).abs() < 1e-9));
    assert_eq!(r.meta.source_format, "cif");
    assert_eq!(r.meta.n_atoms, 8);
}

#[test]
fn op_loop_with_id_column_is_accepted() {
    let src = NACL_OPS.replace(
        "loop_\n_symmetry_equiv_pos_as_xyz\n'x, y, z'",
        "loop_\n_symmetry_equiv_pos_site_id\n_symmetry_equiv_pos_as_xyz\n1 'x, y, z'",
    );
    // give the remaining 6 ops their id column too
    let src = src
        .replace("'z, x, y'", "2 'z, x, y'")
        .replace("'y, z, x'", "3 'y, z, x'")
        .replace("'-x, -y, -z'", "4 '-x, -y, -z'")
        .replace("'x, y+1/2, z+1/2'", "5 'x, y+1/2, z+1/2'")
        .replace("'1/2+x, y, 1/2+z'", "6 '1/2+x, y, 1/2+z'")
        .replace("'x+1/2, y+1/2, z'", "7 'x+1/2, y+1/2, z'");
    let r = cif::parse(&src).unwrap();
    assert_eq!(r.atoms.len(), 8);
}

#[test]
fn alternate_symop_tag_is_accepted() {
    let src = NACL_OPS.replace("_symmetry_equiv_pos_as_xyz", "_space_group_symop_operation_xyz");
    assert_eq!(cif::parse(&src).unwrap().atoms.len(), 8);
}

// ---- sub-path 2: spacegroup identifier ----

#[test]
fn identifier_cif_returns_asym_unit() {
    let r = cif::parse(NACL_SG).unwrap();
    assert_eq!(r.spacegroup, Some(225));
    assert!(r.atoms.is_empty(), "identifier path defers expansion to Typst");
    let asym = r.asym_unit.unwrap();
    assert_eq!(asym.len(), 2);
    assert_eq!(asym[0].element, "Na");
    assert_eq!(asym[1].element, "Cl");
    assert!(close3f(asym[1].frac, [0.5, 0.0, 0.0]));
    assert_eq!(r.meta.n_atoms, 2);
}

#[test]
fn hm_symbol_maps_to_number() {
    let src = NACL_SG.replace("_space_group_IT_number 225", "_symmetry_space_group_name_H-M 'F m -3 m'");
    assert_eq!(cif::parse(&src).unwrap().spacegroup, Some(225));
}

#[test]
fn unknown_hm_symbol_is_error_with_advice() {
    let src = NACL_SG.replace("_space_group_IT_number 225", "_symmetry_space_group_name_H-M 'Q z z'");
    let err = cif::parse(&src).unwrap_err();
    assert!(err.contains("_space_group_IT_number"), "err was: {}", err);
}

#[test]
fn out_of_range_it_number_is_error() {
    let src = NACL_SG.replace("_space_group_IT_number 225", "_space_group_IT_number 999");
    assert!(cif::parse(&src).is_err());
}

// ---- rejections ----

#[test]
fn no_symmetry_is_rejected_naming_tags() {
    let err = cif::parse(NACL_NOSYM).unwrap_err();
    for tag in ["_symmetry_equiv_pos_as_xyz", "_space_group_symop_operation_xyz",
                "_space_group_IT_number", "_symmetry_space_group_name_H-M"] {
        assert!(err.contains(tag), "error must name {}, was: {}", tag, err);
    }
}

#[test]
fn partial_occupancy_is_rejected() {
    let src = NACL_SG
        .replace("_atom_site_fract_z", "_atom_site_fract_z\n_atom_site_occupancy")
        .replace("Na 0.0 0.0 0.0", "Na 0.0 0.0 0.0 0.5")
        .replace("Cl 0.5 0.0 0.0", "Cl 0.5 0.0 0.0 1.0");
    let err = cif::parse(&src).unwrap_err();
    assert!(err.contains("occupancy"), "err was: {}", err);
}

#[test]
fn full_occupancy_column_is_fine() {
    let src = NACL_SG
        .replace("_atom_site_fract_z", "_atom_site_fract_z\n_atom_site_occupancy")
        .replace("Na 0.0 0.0 0.0", "Na 0.0 0.0 0.0 1.0")
        .replace("Cl 0.5 0.0 0.0", "Cl 0.5 0.0 0.0 1.0");
    assert_eq!(cif::parse(&src).unwrap().asym_unit.unwrap().len(), 2);
}

#[test]
fn multiple_data_blocks_are_rejected() {
    let src = format!("{}\ndata_second\n_cell_length_a 1.0\n", NACL_OPS);
    let err = cif::parse(&src).unwrap_err();
    assert!(err.contains("data_"), "err was: {}", err);
}

#[test]
fn ragged_loop_is_rejected() {
    let src = NACL_OPS.replace("Cl1 0.5 0.0 0.0", "Cl1 0.5 0.0"); // 3 of 4 columns
    let err = cif::parse(&src).unwrap_err();
    assert!(err.contains("loop"), "err was: {}", err);
}

#[test]
fn missing_cell_tag_is_named() {
    let src = NACL_SG.replace("_cell_length_b 5.64\n", "");
    let err = cif::parse(&src).unwrap_err();
    assert!(err.contains("_cell_length_b"), "err was: {}", err);
}

// ---- value handling ----

#[test]
fn uncertainty_suffix_is_stripped() {
    let src = NACL_SG.replace("_cell_length_a 5.64", "_cell_length_a 5.64(2)");
    let r = cif::parse(&src).unwrap();
    assert!(close(r.lattice.unwrap()[0][0], 5.64));
}

#[test]
fn comments_and_text_blocks_are_skipped() {
    let src = format!(";\nfree prose that must be ignored\n;\n{}", NACL_SG);
    assert_eq!(cif::parse(&src).unwrap().spacegroup, Some(225));
}
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `cargo test --manifest-path wyckoff-io/Cargo.toml`
Expected: FAIL — `unresolved import wyckoff_io::cif`.

- [ ] **Step 5: Implement `cif.rs`**

Create `wyckoff-io/src/cif.rs`. The op parser, op application, and element normalization are given complete below — use them verbatim. Implement the tokenizer and `parse` exactly per the specification block above (the Step 3 tests pin every behavior; any deviation fails a named test).

```rust
//! Pragmatic CIF subset parser. Supported: a single data_ block, cell
//! parameters, one atom-site loop, and symmetry via an explicit op loop
//! (applied here) or a spacegroup identifier (returned for Typst table
//! expansion). Rejected with precise errors: multiple data blocks, partial
//! occupancy, malformed loops, and files with neither ops nor identifier.

use crate::geom::{cell_to_vectors, frac_to_cart, wrap01};
use crate::record::{AsymAtom, Atom, Meta, Record};
use crate::sg_symbols::SG_SYMBOLS;
use std::collections::HashMap;

/// Fractional-coordinate tolerance when deduplicating op images (periodic
/// min-image). File coordinates are low-precision; distinct atoms are far apart.
const DEDUP_EPS: f64 = 1e-3;

pub struct SymOp {
    pub rot: [[i32; 3]; 3],
    pub trans: [f64; 3],
}

/// Parse one symmetry-op string like "-y+1/2, x-y, z" into rot + trans.
/// Grammar: see the Stage 2 plan (Task 4). Whitespace ignored, case-insensitive.
pub fn parse_op(s: &str) -> Result<SymOp, String> {
    let comps: Vec<&str> = s.split(',').collect();
    if comps.len() != 3 {
        return Err(format!("symmetry op '{}' must have 3 comma-separated components", s));
    }
    let mut rot = [[0i32; 3]; 3];
    let mut trans = [0.0f64; 3];
    for (i, comp) in comps.iter().enumerate() {
        let chars: Vec<char> = comp.chars().filter(|c| !c.is_whitespace()).collect();
        if chars.is_empty() {
            return Err(format!("symmetry op '{}': component {} is empty", s, i + 1));
        }
        let mut k = 0;
        while k < chars.len() {
            let mut sign = 1i32;
            while k < chars.len() && (chars[k] == '+' || chars[k] == '-') {
                if chars[k] == '-' {
                    sign = -sign;
                }
                k += 1;
            }
            if k >= chars.len() {
                return Err(format!("symmetry op '{}': dangling sign in component {}", s, i + 1));
            }
            let c = chars[k].to_ascii_lowercase();
            if c == 'x' || c == 'y' || c == 'z' {
                rot[i][(c as u8 - b'x') as usize] += sign;
                k += 1;
            } else if c.is_ascii_digit() || c == '.' {
                let start = k;
                while k < chars.len() && (chars[k].is_ascii_digit() || chars[k] == '.') {
                    k += 1;
                }
                let numtok: String = chars[start..k].iter().collect();
                let val = if k < chars.len() && chars[k] == '/' {
                    k += 1;
                    let dstart = k;
                    while k < chars.len() && chars[k].is_ascii_digit() {
                        k += 1;
                    }
                    let dentok: String = chars[dstart..k].iter().collect();
                    let n: f64 = numtok.parse().map_err(|_| format!("symmetry op '{}': bad numerator '{}'", s, numtok))?;
                    let d: f64 = dentok.parse().map_err(|_| format!("symmetry op '{}': bad denominator '{}'", s, dentok))?;
                    if d == 0.0 {
                        return Err(format!("symmetry op '{}': division by zero", s));
                    }
                    n / d
                } else {
                    numtok.parse().map_err(|_| format!("symmetry op '{}': bad number '{}'", s, numtok))?
                };
                trans[i] += sign as f64 * val;
            } else {
                return Err(format!("symmetry op '{}': unexpected character '{}'", s, chars[k]));
            }
        }
        trans[i] = wrap01(trans[i]);
    }
    Ok(SymOp { rot, trans })
}

/// q = R·f + t, each component wrapped into [0, 1).
pub fn apply_op(op: &SymOp, f: [f64; 3]) -> [f64; 3] {
    [0, 1, 2].map(|i| {
        wrap01(op.rot[i][0] as f64 * f[0] + op.rot[i][1] as f64 * f[1] + op.rot[i][2] as f64 * f[2] + op.trans[i])
    })
}

/// Derive an element symbol from a CIF type_symbol or label token:
/// "Na1" -> "Na", "O2-" -> "O", "NA" -> "Na", "Ca2+" -> "Ca".
pub fn element_symbol(token: &str) -> Result<String, String> {
    let alpha: String = token.chars().take_while(|c| c.is_ascii_alphabetic()).collect();
    if alpha.is_empty() || alpha.len() > 2 {
        return Err(format!("cannot derive an element symbol from '{}'", token));
    }
    Ok(alpha
        .chars()
        .enumerate()
        .map(|(i, ch)| if i == 0 { ch.to_ascii_uppercase() } else { ch.to_ascii_lowercase() })
        .collect())
}

fn frac_close(p: [f64; 3], q: [f64; 3]) -> bool {
    p.iter().zip(&q).all(|(a, b)| {
        let d = (a - b).abs();
        d.min((d - 1.0).abs()) < DEDUP_EPS
    })
}

struct Loop {
    tags: Vec<String>,          // lowercased, in column order
    rows: Vec<Vec<String>>,     // each row has tags.len() values (quotes stripped)
}

struct Cif {
    scalars: HashMap<String, String>, // lowercased tag -> value (quotes stripped)
    loops: Vec<Loop>,
}

fn find_loop<'a>(cif: &'a Cif, tag: &str) -> Option<(&'a Loop, usize)> {
    cif.loops.iter().find_map(|lp| lp.tags.iter().position(|t| t == tag).map(|i| (lp, i)))
}

/// Strip a trailing "(su)" uncertainty suffix and parse; "." / "?" are errors.
fn num(v: &str) -> Result<f64, String> {
    let base = match v.find('(') {
        Some(i) => &v[..i],
        None => v,
    };
    if base == "." || base == "?" || base.is_empty() {
        return Err(format!("CIF value '{}' is unknown/absent where a number is required", v));
    }
    base.parse().map_err(|_| format!("CIF value '{}' is not a number", v))
}

/// Tokenize per the Stage 2 plan spec: semicolon text blocks skipped, quoted
/// tokens ('...'/"...") kept whole with quotes stripped, '#' comments ended at
/// end of line, loop_ / data_ keywords case-insensitive, tags lowercased,
/// loop value count must be an exact multiple of the column count
/// (else Err containing "malformed loop" and the first column tag),
/// >1 data_ block is an error.
fn tokenize(input: &str) -> Result<Cif, String> {
    // IMPLEMENT PER SPEC — pinned by the tests in wyckoff-io/tests/cif.rs:
    //   comments_and_text_blocks_are_skipped, op_loop_with_id_column_is_accepted,
    //   multiple_data_blocks_are_rejected, ragged_loop_is_rejected,
    //   uncertainty_suffix_is_stripped (scalar on same line), plus every
    //   full-file test (quoted op strings contain commas and spaces).
    todo!()
}

pub fn parse(input: &str) -> Result<Record, String> {
    let cif = tokenize(input)?;

    // 1. Cell parameters -> lattice vectors.
    let mut cell = [0.0f64; 6];
    for (k, tag) in ["_cell_length_a", "_cell_length_b", "_cell_length_c",
                     "_cell_angle_alpha", "_cell_angle_beta", "_cell_angle_gamma"]
        .iter()
        .enumerate()
    {
        let v = cif.scalars.get(*tag).ok_or_else(|| format!("CIF is missing required tag {}", tag))?;
        cell[k] = num(v)?;
    }
    let lattice = cell_to_vectors(cell[0], cell[1], cell[2], cell[3], cell[4], cell[5])?;

    // 2. Asymmetric unit from the atom-site loop.
    let (site_loop, xcol) = find_loop(&cif, "_atom_site_fract_x")
        .ok_or("CIF has no atom-site loop (_atom_site_fract_x/_y/_z)")?;
    let col = |tag: &str| site_loop.tags.iter().position(|t| t == tag);
    let ycol = col("_atom_site_fract_y").ok_or("atom-site loop is missing _atom_site_fract_y")?;
    let zcol = col("_atom_site_fract_z").ok_or("atom-site loop is missing _atom_site_fract_z")?;
    let elcol = col("_atom_site_type_symbol")
        .or_else(|| col("_atom_site_label"))
        .ok_or("atom-site loop needs _atom_site_type_symbol or _atom_site_label")?;
    let occcol = col("_atom_site_occupancy");

    let mut asym = Vec::with_capacity(site_loop.rows.len());
    for (i, row) in site_loop.rows.iter().enumerate() {
        if let Some(oc) = occcol {
            let occ = num(&row[oc])?;
            if (occ - 1.0).abs() > 1e-3 {
                return Err(format!(
                    "atom {} has occupancy {}; partial occupancy/disorder is not supported",
                    i + 1, occ
                ));
            }
        }
        asym.push(AsymAtom {
            element: element_symbol(&row[elcol])?,
            frac: [wrap01(num(&row[xcol])?), wrap01(num(&row[ycol])?), wrap01(num(&row[zcol])?)],
        });
    }
    if asym.is_empty() {
        return Err("CIF atom-site loop has no rows".into());
    }

    // 3. Symmetry dispatch (priority order per the M4 design doc).
    let op_loop = find_loop(&cif, "_symmetry_equiv_pos_as_xyz")
        .or_else(|| find_loop(&cif, "_space_group_symop_operation_xyz"));

    if let Some((lp, opcol)) = op_loop {
        // Sub-path 1: apply the file's literal ops, return explicit atoms.
        let ops = lp.rows.iter().map(|row| parse_op(&row[opcol])).collect::<Result<Vec<_>, _>>()?;
        let mut atoms = Vec::new();
        for a in &asym {
            let mut orbit: Vec<[f64; 3]> = Vec::new();
            for op in &ops {
                let q = apply_op(op, a.frac);
                if !orbit.iter().any(|o| frac_close(*o, q)) {
                    orbit.push(q);
                }
            }
            for q in orbit {
                atoms.push(Atom { element: a.element.clone(), cart: frac_to_cart(&lattice, q), frac: Some(q) });
            }
        }
        let n = atoms.len();
        return Ok(Record {
            lattice: Some(lattice),
            atoms,
            spacegroup: None,
            asym_unit: None,
            bonds: None,
            meta: Meta { source_format: "cif".into(), n_atoms: n },
        });
    }

    if let Some(number) = spacegroup_number(&cif)? {
        // Sub-path 2: identifier only — Typst expands through wyckoff's tables.
        let n = asym.len();
        return Ok(Record {
            lattice: Some(lattice),
            atoms: vec![],
            spacegroup: Some(number),
            asym_unit: Some(asym),
            bonds: None,
            meta: Meta { source_format: "cif".into(), n_atoms: n },
        });
    }

    Err("CIF has neither a symmetry-op loop (_symmetry_equiv_pos_as_xyz / \
         _space_group_symop_operation_xyz) nor a spacegroup identifier \
         (_space_group_IT_number / _symmetry_Int_Tables_number / \
         _symmetry_space_group_name_H-M); cannot expand the structure"
        .into())
}

fn spacegroup_number(cif: &Cif) -> Result<Option<i64>, String> {
    for tag in ["_space_group_it_number", "_symmetry_int_tables_number"] {
        if let Some(v) = cif.scalars.get(tag) {
            let n: i64 = v.parse().map_err(|_| format!("{} value '{}' is not an integer", tag, v))?;
            if !(1..=230).contains(&n) {
                return Err(format!("{} must be 1..230, got {}", tag, n));
            }
            return Ok(Some(n));
        }
    }
    if let Some(v) = cif.scalars.get("_symmetry_space_group_name_h-m") {
        let norm: String = v.chars().filter(|c| !c.is_whitespace() && *c != '_' && *c != '\'' && *c != '"').collect();
        return match SG_SYMBOLS.iter().find(|(s, _)| *s == norm) {
            Some((_, n)) => Ok(Some(*n)),
            None => Err(format!(
                "unrecognized H-M spacegroup symbol '{}'; add an explicit _space_group_IT_number",
                v
            )),
        };
    }
    Ok(None)
}
```

- [ ] **Step 6: Wire modules + wasm export in `lib.rs`**

In `wyckoff-io/src/lib.rs`, extend the module list to:

```rust
pub mod cif;
pub mod geom;
pub mod poscar;
pub mod record;
pub mod sg_symbols;
pub mod xyz;
```

and add after `parse_poscar`:

```rust
#[cfg_attr(target_arch = "wasm32", wasm_func)]
pub fn parse_cif(input: &[u8]) -> Result<Vec<u8>, String> {
    let text = std::str::from_utf8(input).map_err(|e| e.to_string())?;
    let record = cif::parse(text)?;
    serde_json::to_vec(&record).map_err(|e| e.to_string())
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cargo test --manifest-path wyckoff-io/Cargo.toml`
Expected: all pass — the full cif battery (grammar, both sub-paths, all six rejection tests, value handling) plus every pre-existing test.

- [ ] **Step 8: Rebuild the plugin**

Run: `make -C wyckoff plugin`
Expected: rebuilds `wyckoff/plugin/wyckoff_io.wasm` (now exporting `parse_cif`). Note the size printed by `ls -l` — the H-M table adds a few KB; anything over ~50 KB growth suggests an accidental dependency.

- [ ] **Step 9: Commit**

```bash
git add wyckoff-io/src/ wyckoff-io/tests/ wyckoff/examples/data/ wyckoff/tests/data/ wyckoff/plugin/wyckoff_io.wasm
git commit -m "feat(wyckoff-io): CIF-subset parser - op-loop application + spacegroup-identifier record (#26)"
```

---

### Task 5: Typst `expand-general` + `import-cif` end-to-end for both sub-paths (issue #26)

**Files:**
- Modify: `wyckoff/src/symmetry.typ` (add `expand-general`)
- Modify: `wyckoff/tests/test-symmetry.typ` (expand-general tests)
- Modify: `wyckoff/src/io.typ` (spacegroup branch in `record-to-structure`; add `import-cif`)
- Modify: `wyckoff/lib.typ` (export `import-cif`)
- Create: `wyckoff/tests/test-import-cif.typ`
- Create: `wyckoff/examples/import-cif.typ`
- Modify: `wyckoff/README.md` (document `import-cif`)

**Interfaces:**
- Consumes: `_io.parse_cif(bytes) -> bytes` (Task 4); `group-data("3d", n)` returning `(symbol, ltype, ops, wyckoff)` with `ops` a list of `[matrix3x3, translation3]`; `_wrap`/`_close` helpers already in `symmetry.typ`; fixtures from Task 4.
- Produces (Typst, `symmetry.typ`): `expand-general(group, asym, periodic, eps: 1e-4)` — `asym` is `((element, (fx, fy, fz)), ..)`; applies every `group.ops` entry to each atom as a general position (`q = op.at(0)·frac + op.at(1)`), wraps periodic dims, dedups per-atom-orbit; returns `((element: .., frac: .., site: i), ..)`. **No multiplicity assertion** — an atom on a special position legitimately yields a smaller orbit (unlike `expand`, which checks against the Wyckoff multiplicity).
- Produces (Typst, `io.typ`): `record-to-structure` gains the identifier branch (`record.spacegroup != none` → table expansion → explicit periodic structure); `import-cif(path) -> structure`.

- [ ] **Step 1: Write the failing `expand-general` tests**

Append to `wyckoff/tests/test-symmetry.typ` (before the final `Symmetry OK` line), and extend the top import line to `#import "/src/symmetry.typ": expand, expand-general`:

```typ
// ---- expand-general: explicit asymmetric-unit atoms as general positions ----

// NaCl in Fm-3m (225): both atoms sit on special positions; each 4-atom orbit.
#let g225 = group-data("3d", 225)
#let p3 = (true, true, true)
#let nacl = expand-general(g225, (("Na", (0.0, 0.0, 0.0)), ("Cl", (0.5, 0.0, 0.0))), p3)
#assert.eq(nacl.len(), 8)
#for want in ((0.0, 0.0, 0.0), (0.0, 0.5, 0.5), (0.5, 0.0, 0.5), (0.5, 0.5, 0.0)) {
  assert(nacl.any(a => a.element == "Na" and frac-close(a.frac, want, p3)),
    message: "expand-general: missing Na at " + repr(want))
}
#for want in ((0.5, 0.0, 0.0), (0.0, 0.5, 0.0), (0.0, 0.0, 0.5), (0.5, 0.5, 0.5)) {
  assert(nacl.any(a => a.element == "Cl" and frac-close(a.frac, want, p3)),
    message: "expand-general: missing Cl at " + repr(want))
}

// Must agree atom-for-atom with the Wyckoff-letter path (4a + 4b of 225).
#let via-wyckoff = expand(g225, (
  (element: "Na", wyckoff: "a", p: (0.0, 0.0, 0.0)),
  (element: "Cl", wyckoff: "b", p: (0.0, 0.0, 0.0)),
), p3)
#assert.eq(via-wyckoff.len(), 8)
#for a in via-wyckoff {
  assert(nacl.any(b => b.element == a.element and frac-close(b.frac, a.frac, p3)),
    message: "expand-general disagrees with expand at " + repr(a.frac))
}

// Rutile TiO2 in P42/mnm (136): unequal orbit sizes — no multiplicity assert.
#let g136 = group-data("3d", 136)
#let rutile = expand-general(g136, (("Ti", (0.0, 0.0, 0.0)), ("O", (0.305, 0.305, 0.0))), p3)
#assert.eq(rutile.len(), 6)
#assert.eq(rutile.filter(a => a.element == "Ti").len(), 2)
#assert.eq(rutile.filter(a => a.element == "O").len(), 4)
#assert(rutile.any(a => a.element == "O" and frac-close(a.frac, (0.805, 0.195, 0.5), p3)),
  message: "rutile O at (1/2+x, 1/2-x, 1/2) missing")
```

(Expected orbits, hand-checked: Ti 2a → {(0,0,0), (½,½,½)}; O 4f with x = 0.305 → {(x,x,0), (−x,−x,0)→(0.695,0.695,0), (½+x,½−x,½)=(0.805,0.195,0.5), (½−x,½+x,½)=(0.195,0.805,0.5)}.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `make pkgroot && TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff test`
Expected: FAIL — `expand-general` is not defined in `symmetry.typ`.

- [ ] **Step 3: Implement `expand-general`**

In `wyckoff/src/symmetry.typ`, after `expand`, add:

```typ
/// Expand explicit asymmetric-unit atoms through a group's operations,
/// treating each as a general position: q = op.0 · frac + op.1 per op,
/// wrapped on periodic dims and deduplicated per-atom-orbit. Used by the CIF
/// spacegroup-identifier import path, where atoms arrive as raw fractional
/// coordinates rather than Wyckoff letters. Unlike expand(), there is no
/// multiplicity assertion: an atom on a special position yields a smaller
/// orbit, which is correct here.
/// asym: ((element, (fx, fy, fz)), ..). Returns ((element, frac, site), ..).
#let expand-general(group, asym, periodic, eps: 1e-4) = {
  let atoms = ()
  for (si, (el, p)) in asym.enumerate() {
    let orbit = ()
    for op in group.ops {
      let q = vadd(mvec(op.at(0), p), op.at(1))
      let q = range(3).map(i => if periodic.at(i) { _wrap(q.at(i)) } else { q.at(i) })
      if not orbit.any(o => _close(o, q, periodic, eps)) {
        orbit.push(q)
      }
    }
    for q in orbit {
      atoms.push((element: el, frac: q, site: si))
    }
  }
  atoms
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff test`
Expected: `tests/test-symmetry.typ` passes with the new expand-general block.

- [ ] **Step 5: Write the failing import test (the two-sub-paths-agree gate)**

Create `wyckoff/tests/test-import-cif.typ`:

```typ
#import "/src/io.typ": import-cif

#let close(p, q) = range(3).all(i => {
  let d = calc.abs(p.at(i) - q.at(i))
  calc.min(d, calc.abs(d - 1.0)) < 1e-6
})

// Sub-path 1: explicit op loop, expanded in Rust.
#let a = import-cif("/examples/data/nacl-ops.cif")
#assert.eq(a.kind, "3d")
#assert.eq(a.periodic, (true, true, true))
#assert.eq(a.atoms.len(), 8)
#assert.eq(a.vectors.at(0), (5.64, 0.0, 0.0))
#assert.eq(a.atoms.filter(x => x.element == "Na").len(), 4)
#assert.eq(a.atoms.filter(x => x.element == "Cl").len(), 4)
#assert(a.atoms.any(x => x.element == "Cl" and close(x.frac, (0.5, 0.5, 0.5))),
  message: "op-loop path: Cl at cell center missing")

// Sub-path 2: spacegroup identifier, expanded through wyckoff's tables.
#let b = import-cif("/examples/data/nacl-sg.cif")
#assert.eq(b.kind, "3d")
#assert.eq(b.atoms.len(), 8)

// THE GATE: the two sub-paths must produce the same atom set.
#for atom in a.atoms {
  assert(b.atoms.any(x => x.element == atom.element and close(x.frac, atom.frac)),
    message: "CIF sub-paths disagree: no " + atom.element + " at " + repr(atom.frac))
}
CIF import OK
```

- [ ] **Step 6: Run the test to verify it fails**

Run: `TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff test`
Expected: FAIL — `import-cif` is not defined in `io.typ`.

- [ ] **Step 7: Implement the io.typ dispatch + `import-cif`**

In `wyckoff/src/io.typ`, extend the imports at the top:

```typ
#import "structure.typ": structure
#import "data.typ": group-data
#import "symmetry.typ": expand-general
```

Replace `record-to-structure` with the three-way dispatch:

```typ
/// Turn a decoded plugin record into a wyckoff structure.
/// - no lattice            -> molecule (Cartesian atoms)
/// - lattice + spacegroup  -> CIF identifier path: expand the asymmetric unit
///                            through wyckoff's spacegroup tables, then build
///                            an explicit periodic structure
/// - lattice, no spacegroup -> explicit periodic (atoms carry frac)
#let record-to-structure(record) = {
  if record.lattice == none {
    structure(atoms: record.atoms.map(a => (a.element, a.cart)))
  } else if record.spacegroup != none {
    let group = group-data("3d", record.spacegroup)
    let expanded = expand-general(
      group,
      record.asym_unit.map(a => (a.element, a.frac)),
      (true, true, true),
    )
    structure(
      lattice: record.lattice,
      atoms: expanded.map(a => (a.element, a.frac)),
    )
  } else {
    structure(
      lattice: record.lattice,
      atoms: record.atoms.map(a => (a.element, a.frac)),
    )
  }
}
```

After `import-poscar`, add:

```typ
/// Read a CIF file (pragmatic subset) and return a periodic structure.
/// Symmetry: an explicit op loop is applied by the plugin; a bare spacegroup
/// identifier is expanded here through wyckoff's tables; files with neither
/// are rejected with an error naming the missing tags.
#let import-cif(path) = {
  let raw = read(path, encoding: none)   // bytes
  let record = json(_io.parse_cif(raw))
  record-to-structure(record)
}
```

In `wyckoff/lib.typ`, change the io import line to:

```typ
#import "src/io.typ": import-xyz, import-poscar, import-cif
```

- [ ] **Step 8: Run the test to verify it passes**

Run: `TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff test`
Expected: `tests/test-import-cif.typ` passes — 8 atoms on both sub-paths and the agreement loop holds; suite ends `All tests passed!`.

- [ ] **Step 9: Verify the negative control (symmetry-less CIF errors clearly)**

Run:

```bash
printf '#import "/lib.typ": import-cif\n#let _ = import-cif("/tests/data/nacl-nosym.cif")\n' > wyckoff/tests/neg-nosym.typ
(TYPST_PACKAGE_PATH="$PWD/_pkgroot" typst compile --root wyckoff wyckoff/tests/neg-nosym.typ /tmp/neg-nosym.pdf; echo "exit=$?")
rm wyckoff/tests/neg-nosym.typ
```

Expected: compile FAILS, `exit=` nonzero, and the error message names the missing tags (`_symmetry_equiv_pos_as_xyz`, `_space_group_IT_number`, ...) — never a silently mis-expanded structure.

- [ ] **Step 10: Add a rendered example**

Create `wyckoff/examples/import-cif.typ`:

```typ
#import "/lib.typ": import-cif, crystal

// The same NaCl cell through both CIF symmetry sub-paths:
// an explicit op loop (applied in Rust) ...
#crystal(import-cif("/examples/data/nacl-ops.cif"), width: 5cm)

// ... and a spacegroup identifier (expanded via wyckoff's tables).
#crystal(import-cif("/examples/data/nacl-sg.cif"), width: 5cm)
```

- [ ] **Step 11: Compile the example and render the image**

Run: `TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff examples && TYPST_PACKAGE_PATH="$PWD/_pkgroot" make -C wyckoff images`
Expected: `examples/import-cif.pdf` compiles; `images/import-cif.png` shows two visually identical 8-atom NaCl cells.

- [ ] **Step 12: Document `import-cif` in the README**

In `wyckoff/README.md`, in the "Importing from files" subsection (after the `import-poscar` paragraph), add:

```markdown
`import-cif(path)` reads a CIF file (pragmatic subset). Symmetry is handled in
priority order: an explicit `_symmetry_equiv_pos_as_xyz` /
`_space_group_symop_operation_xyz` loop is applied directly (the path most
database exports take); otherwise a spacegroup identifier
(`_space_group_IT_number` or an H-M symbol) selects wyckoff's own tables to
expand the asymmetric unit; files with neither — like partial occupancy or
multi-block files — are rejected with an error naming the unsupported feature.

    #import "@preview/wyckoff:0.1.0": import-cif, crystal
    #crystal(import-cif("nacl.cif"))
```

(Same fence-style note as Task 3 Step 8: match the README's existing `import-xyz` snippet style.)

- [ ] **Step 13: Run the full monorepo suite**

Run: `make test`
Expected: all three packages pass (`All package test suites passed!`) — proves no regression in scenery/brillouin or the pre-existing wyckoff paths.

- [ ] **Step 14: Commit**

```bash
git add wyckoff/src/symmetry.typ wyckoff/src/io.typ wyckoff/lib.typ wyckoff/tests/test-symmetry.typ wyckoff/tests/test-import-cif.typ wyckoff/examples/import-cif.typ wyckoff/images/import-cif.png wyckoff/README.md
git commit -m "feat(wyckoff): import-cif end-to-end, both symmetry sub-paths (#26)"
```

---

## Self-Review

**Spec coverage (issues #25–#26 / design doc "Format handling"):**
- #25 POSCAR: VASP 5 Direct + Cartesian (scale applied to lattice *and* Cartesian positions), Selective-dynamics skip, VASP 4 / negative-scale / mismatch rejections → Tasks 2–3. ✓
- #26 CIF sub-path 1 (op loop): tokenizer subset, op-string grammar with pinned test battery, Rust application + wrap + dedup, explicit-atoms record → Task 4. ✓
- #26 CIF sub-path 2 (identifier): IT-number tags + H-M mapping via a generated 230-entry table; `asym_unit`/`spacegroup` record; Typst `expand-general` + `record-to-structure` dispatch → Tasks 4–5. ✓
- #26 sub-path 3 (neither): `Err` naming all four candidate tags, surfaced as a Typst compile error (negative control in Task 5 Step 9). Occupancy, multi-block, and ragged loops rejected with named tests. ✓
- Both sub-paths proven equivalent on the same physical structure (NaCl, 8 atoms) — the Task 5 gate. Bond detection deliberately absent (Stage 4 per the resequenced design). ✓

**Placeholder scan:** every mechanical piece ships complete code (geom, record, POSCAR parser, `parse_op`, `apply_op`, `element_symbol`, `spacegroup_number`, `expand-general`, io.typ dispatch, all fixtures, all tests with exact asserts). The single intentional `todo!()` is the CIF tokenizer body, which has a 7-point spec and is pinned by named tests (`comments_and_text_blocks_are_skipped`, `multiple_data_blocks_are_rejected`, `ragged_loop_is_rejected`, `op_loop_with_id_column_is_accepted`, and every full-file test that depends on quoted-token handling) — a deviation cannot pass the suite.

**Type consistency:** the record schema in Global Constraints matches Task 1's Rust types (`asym_unit: Option<Vec<AsymAtom>>` serializing to array/null, `frac` omitted-when-None kept from Stage 1) and both Typst consumers (`record.spacegroup != none` dispatch; `record.asym_unit.map(a => (a.element, a.frac))`). `cell_to_vectors` reproduces `lattice-vectors` in `wyckoff/src/lattice.typ` term-for-term (verified against the source), so Rust-built and Typst-built cells agree. `group.ops` shape (`[matrix3x3, t3]`, row-major via `mvec`) verified against `spacegroups.json` (225 has 192 ops) and reused unchanged by `expand-general`. Export names (`parse_poscar`/`parse_cif`/`import-poscar`/`import-cif`/`expand-general`) are consistent across producer and consumer tasks.

**Fixture math, hand-checked:** Cu FCC 4 atoms at (0,0,0)+face centers; NaCl 8 atoms (4 Na at (0,0,0)+F-centering, 4 Cl at (½,0,0) orbit incl. (½,½,½)); the 7-op CIF generates exactly that set from the 2-atom asym unit (each op image enumerated in Task 4 Step 2's preamble); rutile 2+4 orbits for the no-multiplicity-assert case. Floating-point asserts use tolerances everywhere a value is computed (only literal pass-throughs like `(3.615, 0.0, 0.0)` and `(5.64, 0.0, 0.0)` — v1 is exactly `(a, 0, 0)` by construction — use `assert.eq`).

**Known risks carried forward:**
- The CIF tokenizer is the fiddliest unwritten piece; the quoted-token rule (ops contain commas/spaces) is the part most likely to be got wrong first — every full-file test fails loudly if so.
- H-M matching is best-effort by design: normalization strips whitespace/underscores against wyckoff's short symbols (`"F m -3 m"` → `Fm-3m` ✓); unrecognized variants error with advice to add `_space_group_IT_number` rather than guessing.
- `cos(90°)` is ~6e-17 in f64, so off-axis lattice components are near-zero, not zero; tests compare with 1e-9 tolerances and Typst tests never `assert.eq` v2/v3.
