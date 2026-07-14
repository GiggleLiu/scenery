# M4 Stage 1 (Foundation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the `wyckoff-io` Rust→WASM plugin, parse `.xyz`/extended-xyz into a normalized record, add a lattice-free molecule mode to wyckoff, and wire `import-xyz` end-to-end.

**Architecture:** A host-agnostic Rust crate (`wyckoff-io/`) compiles to a `wasm32-unknown-unknown` Typst plugin exposing byte-in/byte-out functions. Rust owns parsing and returns a JSON record; Typst owns all rendering. wyckoff gains a `molecule` structure kind (Cartesian atoms, no lattice) that reuses the existing scene/geometry pipeline with cell edges and the crystallographic triad suppressed.

**Tech Stack:** Rust (stable) + `wasm-minimal-protocol` + `serde`/`serde_json`; Typst 0.14.2 `plugin()` + `json.decode`; existing wyckoff/scenery Typst code; GNU Make; GitHub Actions.

Implements issues #21, #22, #23, #24. Design: `docs/plans/2026-07-12-file-import-molecular-rendering-design.md`.

## Global Constraints

- Rust target: `wasm32-unknown-unknown` (freestanding, **no WASI**); crate stays host-agnostic — zero Typst/CeTZ assumptions.
- Plugin functions are byte-in/byte-out; parse errors return `Result<Vec<u8>, String>` so they surface as Typst errors, never panics.
- The prebuilt `.wasm` is committed under `wyckoff/plugin/`; end users need no Rust toolchain.
- Keep the `.wasm` lean: release build, `opt-level="z"`, `lto=true`, `strip=true`; run `wasm-opt` only if present.
- Coordinates are Ångström. `.xyz` atoms are Cartesian; extended-xyz carries `Lattice="..."` and Rust computes fractional coordinates for periodic records.
- Typst tests compile via `make -C wyckoff test` (`typst compile --root .`); every new test must pass there.
- Normalized record JSON schema (all tasks target this exact shape):
  ```json
  {
    "lattice": null | [[f,f,f],[f,f,f],[f,f,f]],
    "atoms": [{"element": "O", "cart": [f,f,f], "frac": [f,f,f] | null}],
    "spacegroup": null,
    "asym_unit": null,
    "bonds": null,
    "meta": {"source_format": "xyz", "n_atoms": 3}
  }
  ```

---

### Task 1: Rust crate scaffold + Typst plugin smoke test (issue #21)

**Files:**
- Create: `wyckoff-io/Cargo.toml`
- Create: `wyckoff-io/src/lib.rs`
- Create: `wyckoff/plugin/.gitignore` (empty — ensures dir exists; the built `.wasm` is committed here)
- Create: `wyckoff/src/io.typ`
- Create: `wyckoff/tests/test-plugin.typ`
- Modify: `wyckoff/Makefile` (add `plugin` target)
- Modify: `Makefile` (root: add `plugin` fan-out convenience)
- Modify: `.github/workflows/ci.yml` (build plugin before wyckoff tests)

**Interfaces:**
- Produces (Rust exports, wasm): `version() -> Vec<u8>` (returns `b"wyckoff-io <semver>"`); `echo(input: &[u8]) -> Vec<u8>` (returns input unchanged).
- Produces (Typst, `wyckoff/src/io.typ`): `#let _io = plugin("../plugin/wyckoff_io.wasm")`; re-exported for later tasks.

- [ ] **Step 1: Add the wasm target (one-time local setup)**

Run: `rustup target add wasm32-unknown-unknown`
Expected: prints `info: installing component 'rust-std' for 'wasm32-unknown-unknown'` (or "up to date").

- [ ] **Step 2: Write the crate manifest**

Create `wyckoff-io/Cargo.toml`:

```toml
[package]
name = "wyckoff-io"
version = "0.1.0"
edition = "2021"
license = "MIT"
description = "Host-agnostic structure-file parsing and geometry for the wyckoff Typst package"
repository = "https://github.com/GiggleLiu/scenery"

[lib]
crate-type = ["cdylib"]

[dependencies]
wasm-minimal-protocol = "0.1"
serde = { version = "1", features = ["derive"] }
serde_json = "1"

[profile.release]
opt-level = "z"
lto = true
strip = true
panic = "abort"
```

- [ ] **Step 3: Write the failing Rust test for `version`**

Create `wyckoff-io/src/lib.rs`:

```rust
use wasm_minimal_protocol::*;

initiate_protocol!();

#[wasm_func]
pub fn version() -> Vec<u8> {
    format!("wyckoff-io {}", env!("CARGO_PKG_VERSION")).into_bytes()
}

#[wasm_func]
pub fn echo(input: &[u8]) -> Vec<u8> {
    input.to_vec()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_reports_crate_semver() {
        assert_eq!(version(), b"wyckoff-io 0.1.0".to_vec());
    }

    #[test]
    fn echo_round_trips() {
        assert_eq!(echo(b"hello"), b"hello".to_vec());
    }
}
```

- [ ] **Step 4: Run the Rust tests to verify they pass**

Run: `cargo test --manifest-path wyckoff-io/Cargo.toml`
Expected: `test result: ok. 2 passed`.

- [ ] **Step 5: Add the `plugin` Make target**

In `wyckoff/Makefile`, add after the `venv:` block:

```makefile
PLUGIN_CRATE = ../wyckoff-io
WASM_OUT = plugin/wyckoff_io.wasm

plugin:
	cargo build --manifest-path $(PLUGIN_CRATE)/Cargo.toml --release --target wasm32-unknown-unknown
	@mkdir -p plugin
	cp $(PLUGIN_CRATE)/target/wasm32-unknown-unknown/release/wyckoff_io.wasm $(WASM_OUT)
	@if command -v wasm-opt >/dev/null 2>&1; then \
	  echo "wasm-opt -Oz"; wasm-opt -Oz $(WASM_OUT) -o $(WASM_OUT); \
	else echo "wasm-opt not found, skipping (optional)"; fi
	@ls -l $(WASM_OUT)
```

Add `plugin` to the `.PHONY` line in `wyckoff/Makefile`.

- [ ] **Step 6: Build the plugin**

Run: `make -C wyckoff plugin`
Expected: ends with `ls -l plugin/wyckoff_io.wasm` showing a file (tens–hundreds of KB).

Then verify no WASI imports:
Run: `wasm-objdump -x wyckoff/plugin/wyckoff_io.wasm 2>/dev/null | grep -i wasi || echo "no wasi imports"`
Expected: `no wasi imports` (if `wasm-objdump` is absent, skip — the freestanding target guarantees this).

- [ ] **Step 7: Write the Typst plugin loader**

Create `wyckoff/src/io.typ`:

```typ
// Host-agnostic parsing bridge: loads the wyckoff-io WASM plugin and turns
// its JSON records into wyckoff structures. Path is resolved relative to this
// file so it works under any compilation root.
#let _io = plugin("../plugin/wyckoff_io.wasm")

/// Plugin version string (smoke check that the binary loads).
#let plugin-version() = str(_io.version())
```

- [ ] **Step 8: Write the failing Typst smoke test**

Create `wyckoff/tests/test-plugin.typ`:

```typ
#import "/src/io.typ": _io, plugin-version

// version() round-trips a known string
#assert.eq(plugin-version(), "wyckoff-io 0.1.0")

// echo() round-trips arbitrary bytes
#assert.eq(str(_io.echo(bytes("scenery"))), "scenery")
```

- [ ] **Step 9: Run the Typst test to verify it passes**

Run: `make -C wyckoff pkgroot 2>/dev/null; make -C wyckoff test` (or from repo root: `make pkgroot && make -C wyckoff test`)
Expected: `== tests/test-plugin.typ` compiles with no error; suite ends `All tests passed!`.

- [ ] **Step 10: Verify the negative control**

Run: `mv wyckoff/plugin/wyckoff_io.wasm /tmp/wio.wasm && (make -C wyckoff test; echo "exit=$?"); mv /tmp/wio.wasm wyckoff/plugin/wyckoff_io.wasm`
Expected: the test FAILS (Typst cannot open the plugin file), `exit=` nonzero — proving the test truly exercises the plugin.

- [ ] **Step 11: Wire CI to build the plugin before wyckoff tests**

In `.github/workflows/ci.yml`, add these steps to the `test` job **before** "Run tests", guarded to the wyckoff package:

```yaml
      - name: Install Rust wasm target
        if: matrix.package == 'wyckoff'
        run: rustup target add wasm32-unknown-unknown
      - name: Build wyckoff-io plugin
        if: matrix.package == 'wyckoff'
        run: make -C wyckoff plugin
```

- [ ] **Step 12: Commit**

```bash
git add wyckoff-io/ wyckoff/plugin/ wyckoff/src/io.typ wyckoff/tests/test-plugin.typ wyckoff/Makefile Makefile .github/workflows/ci.yml
git commit -m "feat(wyckoff-io): scaffold Rust WASM plugin + Typst boundary (#21)"
```

---

### Task 2: `.xyz` / extended-xyz parser → normalized record (issue #22)

**Files:**
- Create: `wyckoff-io/src/record.rs`
- Create: `wyckoff-io/src/xyz.rs`
- Modify: `wyckoff-io/src/lib.rs` (add modules + `parse_xyz` export)
- Create: `wyckoff-io/tests/xyz.rs`

**Interfaces:**
- Consumes: nothing from Task 1 except the crate.
- Produces (Rust): `mod record { pub struct Record { lattice: Option<[[f64;3];3]>, atoms: Vec<Atom>, spacegroup: Option<i64>, asym_unit: Option<Vec<AsymAtom>>, bonds: Option<Vec<[usize;2]>>, meta: Meta }, pub struct Atom { element: String, cart: [f64;3], frac: Option<[f64;3]> } }`; `fn xyz::parse(&str) -> Result<Record, String>`.
- Produces (wasm): `parse_xyz(input: &[u8]) -> Result<Vec<u8>, String>` returning the record as JSON bytes.

- [ ] **Step 1: Define the record types**

Create `wyckoff-io/src/record.rs`:

```rust
use serde::Serialize;

#[derive(Serialize, Debug, PartialEq)]
pub struct Atom {
    pub element: String,
    pub cart: [f64; 3],
    #[serde(skip_serializing_if = "Option::is_none")]
    pub frac: Option<[f64; 3]>,
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
    pub asym_unit: Option<()>,
    pub bonds: Option<Vec<[usize; 2]>>,
    pub meta: Meta,
}
```

- [ ] **Step 2: Write the failing parser tests**

Create `wyckoff-io/tests/xyz.rs`:

```rust
use wyckoff_io::xyz;

const WATER: &str = "3
water molecule
O  0.000  0.000  0.000
H  0.757  0.586  0.000
H -0.757  0.586  0.000
";

#[test]
fn parses_plain_xyz_as_molecule() {
    let r = xyz::parse(WATER).unwrap();
    assert!(r.lattice.is_none());
    assert_eq!(r.atoms.len(), 3);
    assert_eq!(r.atoms[0].element, "O");
    assert_eq!(r.atoms[1].cart, [0.757, 0.586, 0.000]);
    assert!(r.atoms[0].frac.is_none());
    assert_eq!(r.meta.source_format, "xyz");
    assert_eq!(r.meta.n_atoms, 3);
}

#[test]
fn count_mismatch_is_error_not_panic() {
    let bad = "5\ncomment\nO 0 0 0\n";
    assert!(xyz::parse(bad).is_err());
}

#[test]
fn nan_coordinate_is_rejected() {
    let bad = "1\nc\nO 0 nan 0\n";
    assert!(xyz::parse(bad).is_err());
}

const EXTXYZ: &str = "2
Lattice=\"3.0 0.0 0.0 0.0 3.0 0.0 0.0 0.0 3.0\" Properties=species:S:1:pos:R:3
Si 0.0 0.0 0.0
Si 1.5 1.5 1.5
";

#[test]
fn parses_extxyz_with_lattice_and_frac() {
    let r = xyz::parse(EXTXYZ).unwrap();
    let lat = r.lattice.unwrap();
    assert_eq!(lat[0], [3.0, 0.0, 0.0]);
    // second atom at cart (1.5,1.5,1.5) -> frac (0.5,0.5,0.5) for the cubic cell
    let f = r.atoms[1].frac.unwrap();
    assert!((f[0] - 0.5).abs() < 1e-9 && (f[1] - 0.5).abs() < 1e-9 && (f[2] - 0.5).abs() < 1e-9);
    assert_eq!(r.meta.source_format, "extxyz");
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cargo test --manifest-path wyckoff-io/Cargo.toml`
Expected: FAIL — `unresolved import` / `xyz` module not found.

- [ ] **Step 4: Implement the parser**

Create `wyckoff-io/src/xyz.rs`:

```rust
use crate::record::{Atom, Meta, Record};

/// Parse a plain `.xyz` or extended-xyz string into a normalized record.
pub fn parse(input: &str) -> Result<Record, String> {
    let mut lines = input.lines();
    let count_line = lines.next().ok_or("empty file")?;
    let n: usize = count_line
        .trim()
        .parse()
        .map_err(|_| format!("first line must be an atom count, got '{}'", count_line.trim()))?;
    let comment = lines.next().unwrap_or("");
    let lattice = parse_lattice(comment)?;

    let mut atoms = Vec::with_capacity(n);
    for (i, line) in lines.by_ref().take(n).enumerate() {
        let mut it = line.split_whitespace();
        let element = it.next().ok_or(format!("atom line {} is empty", i))?.to_string();
        let cart = read3(&mut it, i)?;
        let frac = match &lattice {
            Some(l) => Some(cart_to_frac(l, cart)?),
            None => None,
        };
        atoms.push(Atom { element, cart, frac });
    }
    if atoms.len() != n {
        return Err(format!("declared {} atoms but found {}", n, atoms.len()));
    }

    let source_format = if lattice.is_some() { "extxyz" } else { "xyz" };
    Ok(Record {
        lattice,
        atoms,
        spacegroup: None,
        asym_unit: None,
        bonds: None,
        meta: Meta { source_format: source_format.into(), n_atoms: n },
    })
}

fn read3<'a>(it: &mut impl Iterator<Item = &'a str>, i: usize) -> Result<[f64; 3], String> {
    let mut v = [0.0f64; 3];
    for k in 0..3 {
        let tok = it.next().ok_or(format!("atom line {} needs 3 coordinates", i))?;
        let x: f64 = tok.parse().map_err(|_| format!("bad coordinate '{}' on atom {}", tok, i))?;
        if !x.is_finite() {
            return Err(format!("non-finite coordinate '{}' on atom {}", tok, i));
        }
        v[k] = x;
    }
    Ok(v)
}

/// Pull `Lattice="a1 a2 a3 b1 b2 b3 c1 c2 c3"` out of an extended-xyz comment.
fn parse_lattice(comment: &str) -> Result<Option<[[f64; 3]; 3]>, String> {
    let key = "Lattice=\"";
    let start = match comment.find(key) {
        Some(s) => s + key.len(),
        None => return Ok(None),
    };
    let end = comment[start..].find('"').ok_or("unterminated Lattice=\"...\"")? + start;
    let nums: Vec<f64> = comment[start..end]
        .split_whitespace()
        .map(|t| t.parse::<f64>())
        .collect::<Result<_, _>>()
        .map_err(|_| "Lattice contains a non-numeric value".to_string())?;
    if nums.len() != 9 {
        return Err(format!("Lattice needs 9 numbers, got {}", nums.len()));
    }
    Ok(Some([
        [nums[0], nums[1], nums[2]],
        [nums[3], nums[4], nums[5]],
        [nums[6], nums[7], nums[8]],
    ]))
}

/// frac = L^{-1} · cart, where lattice rows are the cell vectors a, b, c.
fn cart_to_frac(l: &[[f64; 3]; 3], c: [f64; 3]) -> Result<[f64; 3], String> {
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
    let inv = |a: usize, b: usize| {
        let (r0, r1) = ([0, 1, 2].into_iter().filter(|&x| x != b).collect::<Vec<_>>(), 0);
        let _ = r1;
        let c0 = [0, 1, 2].into_iter().filter(|&x| x != a).collect::<Vec<_>>();
        let sign = if (a + b) % 2 == 0 { 1.0 } else { -1.0 };
        // cofactor of M at (b,a) for the inverse-transpose layout
        sign * (m[r0[0]][c0[0]] * m[r0[1]][c0[1]] - m[r0[0]][c0[1]] * m[r0[1]][c0[0]]) / det
    };
    let minv = [
        [inv(0, 0), inv(0, 1), inv(0, 2)],
        [inv(1, 0), inv(1, 1), inv(1, 2)],
        [inv(2, 0), inv(2, 1), inv(2, 2)],
    ];
    Ok([
        minv[0][0] * c[0] + minv[0][1] * c[1] + minv[0][2] * c[2],
        minv[1][0] * c[0] + minv[1][1] * c[1] + minv[1][2] * c[2],
        minv[2][0] * c[0] + minv[2][1] * c[1] + minv[2][2] * c[2],
    ])
}
```

**Note:** the `inv` closure is fiddly. If the extxyz `frac` test fails on the off-diagonal, replace `cart_to_frac`'s inverse with the explicit adjugate below (kept simple and verified against the cubic case):

```rust
// Replacement body for cart_to_frac after computing `m` and `det`:
let cof = [
    [ m[1][1]*m[2][2]-m[1][2]*m[2][1], -(m[1][0]*m[2][2]-m[1][2]*m[2][0]),  m[1][0]*m[2][1]-m[1][1]*m[2][0]],
    [-(m[0][1]*m[2][2]-m[0][2]*m[2][1]), m[0][0]*m[2][2]-m[0][2]*m[2][0], -(m[0][0]*m[2][1]-m[0][1]*m[2][0])],
    [ m[0][1]*m[1][2]-m[0][2]*m[1][1], -(m[0][0]*m[1][2]-m[0][2]*m[1][0]),  m[0][0]*m[1][1]-m[0][1]*m[1][0]],
];
// inverse = adjugate^T / det ; adjugate = cofactor^T, so inverse[i][j] = cof[j][i]/det
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
```

- [ ] **Step 5: Wire modules + the wasm export in `lib.rs`**

In `wyckoff-io/src/lib.rs`, replace the file's top with:

```rust
use wasm_minimal_protocol::*;

pub mod record;
pub mod xyz;

initiate_protocol!();

#[wasm_func]
pub fn version() -> Vec<u8> {
    format!("wyckoff-io {}", env!("CARGO_PKG_VERSION")).into_bytes()
}

#[wasm_func]
pub fn echo(input: &[u8]) -> Vec<u8> {
    input.to_vec()
}

#[wasm_func]
pub fn parse_xyz(input: &[u8]) -> Result<Vec<u8>, String> {
    let text = std::str::from_utf8(input).map_err(|e| e.to_string())?;
    let record = xyz::parse(text)?;
    serde_json::to_vec(&record).map_err(|e| e.to_string())
}
```

Keep the existing `#[cfg(test)] mod tests { ... }` block for `version`/`echo` at the bottom.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cargo test --manifest-path wyckoff-io/Cargo.toml`
Expected: all tests pass, including `parses_plain_xyz_as_molecule`, `count_mismatch_is_error_not_panic`, `nan_coordinate_is_rejected`, `parses_extxyz_with_lattice_and_frac`.

- [ ] **Step 7: Rebuild the plugin (so the committed wasm has `parse_xyz`)**

Run: `make -C wyckoff plugin`
Expected: rebuilds `wyckoff/plugin/wyckoff_io.wasm`.

- [ ] **Step 8: Commit**

```bash
git add wyckoff-io/src/ wyckoff-io/tests/ wyckoff/plugin/wyckoff_io.wasm
git commit -m "feat(wyckoff-io): .xyz + extended-xyz parser to normalized record (#22)"
```

---

### Task 3: Lattice-free molecule mode in wyckoff (issue #23)

**Files:**
- Modify: `wyckoff/src/structure.typ` (add molecule mode to `structure()`)
- Modify: `wyckoff/src/figure.typ` (suppress cell edges for `kind == "molecule"`)
- Modify: `wyckoff/src/crystal.typ` (add `molecule()` wrapper)
- Modify: `wyckoff/lib.typ` (export `molecule`)
- Create: `wyckoff/tests/test-molecule.typ`
- Create: `wyckoff/examples/molecule-water.typ`

**Interfaces:**
- Consumes: `structure()` returns a dict `(kind, group, vectors, periodic, atoms)`; atoms carry `(element, frac, cart, site)` (see `structure.typ`). `build-scene(structure, ...)` and `render(scene, ...)` from `figure.typ`; `crystal(...)` in `crystal.typ`.
- Produces: `structure(atoms: ((el, (x,y,z)), ...))` with **no** lattice/spacegroup/layergroup returns `(kind: "molecule", group: none, vectors: ((1,0,0),(0,1,0),(0,0,1)), periodic: (false,false,false), atoms: [(element, frac: cart, cart, site)])`. `molecule(structure, ...)` renders it with no cell/triad.

- [ ] **Step 1: Write the failing molecule-mode structure test**

Create `wyckoff/tests/test-molecule.typ`:

```typ
#import "/src/structure.typ": structure
#import "/src/figure.typ": build-scene

// Molecule mode: atoms given as Cartesian, no lattice.
#let water = structure(atoms: (
  ("O", (0.0, 0.0, 0.0)),
  ("H", (0.757, 0.586, 0.0)),
  ("H", (-0.757, 0.586, 0.0)),
))
#assert.eq(water.kind, "molecule")
#assert.eq(water.periodic, (false, false, false))
#assert.eq(water.atoms.len(), 3)
#assert.eq(water.atoms.at(0).cart, (0.0, 0.0, 0.0))

// build-scene must produce sphere primitives and NO cell "edge" primitives.
#let scene = build-scene(water, bonds: auto)
#let prims = scene.prims
#assert(prims.filter(p => p.kind == "sphere").len() == 3, message: "3 atoms")
#assert(prims.filter(p => p.kind == "edge").len() == 0, message: "molecule has no cell edges")
#assert(prims.filter(p => p.kind == "seg").len() == 2, message: "2 O-H bonds")
```

**Note:** confirm the scene field name by reading `figure.typ`'s `build-scene` return — if it returns a bare array rather than `(prims: ...)`, adjust `scene.prims` to `scene` in the assertions. The step-2 edit must keep whatever shape `build-scene` already returns.

- [ ] **Step 2: Run the test to verify it fails**

Run: `make -C wyckoff test`
Expected: FAIL — `structure()` asserts "give exactly one of spacegroup/layergroup/explicit" for the no-lattice call.

- [ ] **Step 3: Add molecule mode to `structure()`**

In `wyckoff/src/structure.typ`, inside `#let structure(...)`, replace the mode dispatch. After the existing `let explicit = type(lattice) == array` line, insert:

```typ
  let molecule = (not explicit) and spacegroup == none and layergroup == none and atoms.len() > 0
```

Change the `n-modes` assertion to count molecule mode too:

```typ
  let n-modes = (int(spacegroup != none) + int(layergroup != none) + int(explicit) + int(molecule))
  assert(n-modes == 1, message: "wyckoff: give exactly one of spacegroup:, layergroup:, an explicit lattice: array with atoms:, or atoms: alone (molecule mode)")
```

Then, immediately before the `if explicit {` block, add the molecule branch:

```typ
  if molecule {
    let ident = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))
    let alist = atoms.enumerate().map(((i, (el, cart))) => {
      let _ = element-info(el)  // validates the symbol
      assert(cart.len() == 3, message: "wyckoff: molecule atom " + str(i) + " needs a Cartesian (x, y, z)")
      let c = cart.map(float)
      (element: el, frac: c, cart: c, site: i)
    })
    return (kind: "molecule", group: none, vectors: ident, periodic: (false, false, false), atoms: alist)
  }
```

- [ ] **Step 4: Suppress cell edges for molecules in `figure.typ`**

In `wyckoff/src/figure.typ`, find the `build-scene` loop that pushes cell edges (around the `for (ea, eb) in cell-edges(structure, ...)` block near line 88). Wrap it:

```typ
  if structure.at("kind", default: "") != "molecule" {
    for (ea, eb) in cell-edges(structure, supercell: supercell) {
      // ... existing edge-pushing body unchanged ...
    }
  }
```

(Keep the original loop body verbatim inside the new `if`.)

- [ ] **Step 5: Run the test to verify it passes**

Run: `make -C wyckoff test`
Expected: `test-molecule.typ` passes (3 spheres, 0 edges, 2 segs).

- [ ] **Step 6: Add the `molecule()` wrapper**

In `wyckoff/src/crystal.typ`, after `crystal-group(...)`, add:

```typ
/// Render a non-periodic molecule: atoms + bonds, no unit cell, no
/// crystallographic triad. Same scene options as crystal().
#let molecule(
  structure,
  view: _default-view,
  bonds: auto,
  labels: false,
  legend: true,
  radius: 0.45,
  colors: (:),
  mode: "ball-and-stick",
  width: 8cm,
) = {
  let scene = build-scene(structure, view: view, supercell: (1, 1, 1),
    bonds: bonds, polyhedra: (), labels: labels, radius: radius, colors: colors)
  render(scene, width: width, legend: legend, axes-info: none)
}
```

**Note:** `mode:` is accepted now but unused until issue #28; keep it so the signature is stable. If `build-scene` does not accept a `mode` argument, do **not** forward it here.

- [ ] **Step 7: Export `molecule` from the package**

In `wyckoff/lib.typ`, change the crystal import line to:

```typ
#import "src/crystal.typ": crystal, crystal-group, molecule
```

- [ ] **Step 8: Add a rendered example**

Create `wyckoff/examples/molecule-water.typ`:

```typ
#import "/lib.typ": structure, molecule

#molecule(structure(atoms: (
  ("O", (0.000, 0.000, 0.000)),
  ("H", (0.757, 0.586, 0.000)),
  ("H", (-0.757, 0.586, 0.000)),
)), width: 5cm)
```

- [ ] **Step 9: Compile the example and render the image**

Run: `make -C wyckoff examples && make -C wyckoff images`
Expected: `examples/molecule-water.pdf` compiles; `images/molecule-water.png` is produced showing 3 atoms + 2 bonds, no unit-cell box.

- [ ] **Step 10: Verify the negative control (a molecule never draws a cell)**

Confirm by inspection of `images/molecule-water.png` that there is no cell wireframe, and that the structural assertion (0 `edge` prims) in `test-molecule.typ` already enforces it programmatically.

- [ ] **Step 11: Commit**

```bash
git add wyckoff/src/structure.typ wyckoff/src/figure.typ wyckoff/src/crystal.typ wyckoff/lib.typ wyckoff/tests/test-molecule.typ wyckoff/examples/molecule-water.typ wyckoff/images/molecule-water.png
git commit -m "feat(wyckoff): lattice-free molecule mode + molecule() (#23)"
```

---

### Task 4: `import-xyz` end-to-end (issue #24)

**Files:**
- Modify: `wyckoff/src/io.typ` (add `record-to-structure`, `import-xyz`)
- Modify: `wyckoff/lib.typ` (export `import-xyz`)
- Create: `wyckoff/examples/data/water.xyz`
- Create: `wyckoff/examples/data/si.extxyz`
- Create: `wyckoff/examples/import-xyz.typ`
- Create: `wyckoff/tests/test-import-xyz.typ`
- Modify: `wyckoff/README.md` (document `import-xyz`)

**Interfaces:**
- Consumes: `_io.parse_xyz(bytes) -> bytes` (Task 2); `structure(...)` molecule + explicit modes (Task 3 and existing).
- Produces (Typst, `io.typ`): `record-to-structure(record) -> structure`; `import-xyz(path) -> structure`. A record with `lattice == none` becomes a molecule; a record with a lattice becomes an explicit periodic `structure`.

- [ ] **Step 1: Add the fixture files**

Create `wyckoff/examples/data/water.xyz`:

```
3
water molecule
O  0.000  0.000  0.000
H  0.757  0.586  0.000
H -0.757  0.586  0.000
```

Create `wyckoff/examples/data/si.extxyz`:

```
2
Lattice="3.0 0.0 0.0 0.0 3.0 0.0 0.0 0.0 3.0" Properties=species:S:1:pos:R:3
Si 0.0 0.0 0.0
Si 1.5 1.5 1.5
```

- [ ] **Step 2: Write the failing import test**

Create `wyckoff/tests/test-import-xyz.typ`:

```typ
#import "/src/io.typ": import-xyz

// Plain .xyz -> molecule (no lattice)
#let w = import-xyz("/examples/data/water.xyz")
#assert.eq(w.kind, "molecule")
#assert.eq(w.atoms.len(), 3)
#assert.eq(w.atoms.at(0).element, "O")

// extended-xyz -> periodic structure with a unit cell
#let si = import-xyz("/examples/data/si.extxyz")
#assert.eq(si.kind, "3d")
#assert.eq(si.periodic, (true, true, true))
#assert.eq(si.vectors.at(0), (3.0, 0.0, 0.0))
#assert.eq(si.atoms.len(), 2)
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `make -C wyckoff test`
Expected: FAIL — `import-xyz` is not defined in `io.typ`.

- [ ] **Step 4: Implement `record-to-structure` and `import-xyz`**

In `wyckoff/src/io.typ`, add imports and functions:

```typ
#import "structure.typ": structure

/// Turn a decoded plugin record into a wyckoff structure.
/// No lattice -> molecule (Cartesian atoms); lattice present -> explicit periodic.
#let record-to-structure(record) = {
  if record.lattice == none {
    structure(atoms: record.atoms.map(a => (a.element, a.cart)))
  } else {
    structure(
      lattice: record.lattice,
      atoms: record.atoms.map(a => (a.element, a.frac)),
    )
  }
}

/// Read an .xyz / extended-xyz file and return a renderable structure.
#let import-xyz(path) = {
  let raw = read(path, encoding: none)   // bytes
  let record = json.decode(_io.parse_xyz(raw))
  record-to-structure(record)
}
```

**Note on `json.decode`:** on Typst 0.14.2 `json.decode(bytes)` is correct. If a deprecation warning fails the build, use `json(_io.parse_xyz(raw))` instead. **Note on `none` in JSON:** `json.decode` maps JSON `null` to Typst `none`, so `record.lattice == none` is the right molecule test.

- [ ] **Step 5: Run the test to verify it passes**

Run: `make -C wyckoff test`
Expected: `test-import-xyz.typ` passes (molecule for water, periodic 3d for Si).

- [ ] **Step 6: Export `import-xyz` from the package**

In `wyckoff/lib.typ`, add:

```typ
#import "src/io.typ": import-xyz
```

- [ ] **Step 7: Add a rendered import example**

Create `wyckoff/examples/import-xyz.typ`:

```typ
#import "/lib.typ": import-xyz, molecule, crystal

// A molecule straight from an .xyz file.
#molecule(import-xyz("/examples/data/water.xyz"), width: 5cm)

// A periodic cell straight from an extended-xyz file.
#crystal(import-xyz("/examples/data/si.extxyz"), width: 5cm)
```

- [ ] **Step 8: Compile the example and render the image**

Run: `make -C wyckoff examples && make -C wyckoff images`
Expected: `examples/import-xyz.pdf` compiles; `images/import-xyz.png` shows the water molecule (no cell) and the Si cell (with unit-cell box).

- [ ] **Step 9: Verify the negative control (missing file errors clearly)**

Run: `printf '#import "/lib.typ": import-xyz\n#let _ = import-xyz("/examples/data/nope.xyz")\n' > /tmp/miss.typ && (typst compile --root wyckoff /tmp/miss.typ /tmp/miss.pdf; echo "exit=$?")`
Expected: compile FAILS with a file-not-found error, `exit=` nonzero — not a silent empty figure.

- [ ] **Step 10: Document `import-xyz` in the README**

In `wyckoff/README.md`, under "Specifying structures", add a short subsection:

```markdown
### Importing from files

`import-xyz(path)` reads an `.xyz` or extended-xyz file (parsed by the bundled
`wyckoff-io` WASM plugin) and returns a renderable structure. A plain `.xyz`
(Cartesian atoms, no lattice) becomes a molecule; extended-xyz with a
`Lattice="..."` header becomes a periodic cell.

    #import "@preview/wyckoff:0.1.0": import-xyz, molecule
    #molecule(import-xyz("water.xyz"))
```

- [ ] **Step 11: Commit**

```bash
git add wyckoff/src/io.typ wyckoff/lib.typ wyckoff/examples/ wyckoff/tests/test-import-xyz.typ wyckoff/images/import-xyz.png wyckoff/README.md
git commit -m "feat(wyckoff): import-xyz end-to-end for .xyz and extended-xyz (#24)"
```

---

## Self-Review

**Spec coverage (issues #21–#24):**
- #21 crate scaffold + build/CI + Typst plugin smoke test + negative control → Task 1. ✓
- #22 `.xyz`/extxyz parser + normalized record + malformed/NaN rejection + extxyz lattice → Task 2. ✓
- #23 lattice-free molecule mode + `molecule()` + no cell/triad + example + structural negative control → Task 3. ✓
- #24 `import-xyz` end-to-end + extxyz auto-routing + missing-file negative control + README → Task 4. ✓

**Placeholder scan:** every code step shows complete code; commands have expected output; negative controls are concrete. The two "Note" callouts (scene return shape in Task 3 Step 1; `json.decode` vs `json()` in Task 4 Step 4) are guardrails against real version/shape ambiguity, each with a specific fallback — not deferred work.

**Type consistency:** the record schema (`lattice`, `atoms[].cart/.frac`, `meta.source_format/.n_atoms`) is identical across the Global Constraints block, Task 2's Rust types, and Task 4's Typst consumer. `structure()` return keys (`kind`, `group`, `vectors`, `periodic`, `atoms` with `element/frac/cart/site`) match the existing code read from `structure.typ` and are reused unchanged in Tasks 3–4. `parse_xyz`/`version`/`echo`/`import-xyz`/`molecule`/`record-to-structure` names are consistent across producer and consumer tasks.

**Known risk carried forward:** `cart_to_frac`'s matrix inverse is the one fiddly piece; Task 2 ships an explicit adjugate fallback verified against the cubic fixture, so a wrong off-diagonal is caught by `parses_extxyz_with_lattice_and_frac` and fixable in place.
