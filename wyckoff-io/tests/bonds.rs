// Rust auto bond-detection (M4 Stage 4, Task 6). These pin the spatial-hash
// implementation to the SAME rule/radii/order as wyckoff's Typst find-bonds
// (geometry.typ:85-111): a pair bonds iff 0.4 <= d <= 1.15 * (r_i + r_j), with
// output sorted ascending (i, j), i < j.
use wyckoff_io::bonds::find_bonds;
use wyckoff_io::radii;

fn atom(el: &str, x: f64, y: f64, z: f64) -> (String, [f64; 3]) {
    (el.to_string(), [x, y, z])
}

// ----- 1. Water: exactly the O-H bonds, not the H-H pair ---------------------
#[test]
fn water_bonds_o_h_only() {
    // The exact coordinates of wyckoff/examples/data/water.xyz.
    let atoms = vec![
        atom("O", 0.000, 0.000, 0.000),
        atom("H", 0.757, 0.586, 0.000),
        atom("H", -0.757, 0.586, 0.000),
    ];
    // O-H ~0.957 <= 1.15*(0.66+0.31)=1.1155 -> bond; H-H ~1.514 > 1.15*0.62 -> not.
    assert_eq!(find_bonds(&atoms), vec![[0, 1], [0, 2]]);
}

// ----- 2. Benzene: 6 ring C-C + 6 radial C-H, no 2nd-neighbour C-C -----------
fn ring(el: &str, r: f64) -> Vec<(String, [f64; 3])> {
    (0..6)
        .map(|k| {
            let a = (k as f64) * std::f64::consts::FRAC_PI_3; // 60 deg steps
            atom(el, r * a.cos(), r * a.sin(), 0.0)
        })
        .collect()
}

#[test]
fn benzene_twelve_bonds() {
    let mut atoms = ring("C", 1.39);
    atoms.extend(ring("H", 2.48));
    let bonds = find_bonds(&atoms);
    // 6 C-C (adjacent, d=1.39 <= 1.679) + 6 C-H (radial, d=1.09 <= 1.196).
    // No 2nd-neighbour C-C (d=2.408 > 1.679); no H-H (d=2.48 > 0.713).
    assert_eq!(bonds.len(), 12);
    // sorted, i < j
    for b in &bonds {
        assert!(b[0] < b[1]);
    }
    let mut sorted = bonds.clone();
    sorted.sort();
    assert_eq!(bonds, sorted);
}

// ----- 3. The 0.4 A floor (min-distance guard) -------------------------------
#[test]
fn floor_rejects_below_point_four() {
    let below = vec![atom("H", 0.0, 0.0, 0.0), atom("H", 0.35, 0.0, 0.0)];
    assert_eq!(find_bonds(&below), Vec::<[usize; 2]>::new());
    let above = vec![atom("H", 0.0, 0.0, 0.0), atom("H", 0.45, 0.0, 0.0)];
    assert_eq!(find_bonds(&above), vec![[0, 1]]);
}

// ----- 4. Spatial hash == O(N^2) brute force on a 200-atom cloud -------------
/// Same rule as find_bonds, but the naive double loop -- the ground truth the
/// spatial hash must reproduce exactly (guards cell-boundary bugs).
fn brute_force(atoms: &[(String, [f64; 3])]) -> Vec<[usize; 2]> {
    let mut out = Vec::new();
    for i in 0..atoms.len() {
        for j in (i + 1)..atoms.len() {
            let (ra, rb) = match (radii::r_cov(&atoms[i].0), radii::r_cov(&atoms[j].0)) {
                (Some(a), Some(b)) => (a, b),
                _ => continue,
            };
            let d = {
                let p = atoms[i].1;
                let q = atoms[j].1;
                let dx = p[0] - q[0];
                let dy = p[1] - q[1];
                let dz = p[2] - q[2];
                (dx * dx + dy * dy + dz * dz).sqrt()
            };
            if d >= 0.4 && d <= 1.15 * (ra + rb) {
                out.push([i, j]);
            }
        }
    }
    out.sort();
    out
}

#[test]
fn spatial_hash_matches_brute_force() {
    // Deterministic pseudo-random cloud (inline LCG, no rand dep). A ~10 A box
    // with 200 mixed atoms puts many pairs inside the cutoff AND straddling
    // cell boundaries, so the 27-cell neighbour scan is genuinely exercised.
    let mut state: u64 = 0x1234_5678_9abc_def0;
    let mut next = || {
        state = state
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        ((state >> 33) as f64) / ((1u64 << 31) as f64) // in [0, 1)
    };
    let els = ["H", "C", "O", "N"];
    let atoms: Vec<(String, [f64; 3])> = (0..200)
        .map(|_| {
            let el = els[(next() * 4.0) as usize % 4];
            atom(el, next() * 10.0, next() * 10.0, next() * 10.0)
        })
        .collect();
    let hash = find_bonds(&atoms);
    let brute = brute_force(&atoms);
    assert_eq!(hash, brute);
    // Sanity: the cloud actually produced bonds (else the test proves nothing).
    assert!(!brute.is_empty(), "test cloud produced no bonds");
}

// ----- 5. Radii drift gate: compiled radii == elements.json's r-cov ----------
#[cfg(not(target_arch = "wasm32"))]
#[test]
fn compiled_radii_match_elements_json() {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../wyckoff/data/elements.json");
    let text = std::fs::read_to_string(path).expect("read elements.json");
    let json: serde_json::Value = serde_json::from_str(&text).expect("parse elements.json");
    let obj = json.as_object().expect("elements.json is an object");
    let mut count = 0;
    for (sym, entry) in obj {
        let want = entry["r-cov"].as_f64().expect("r-cov is a number");
        let got = radii::r_cov(sym).unwrap_or_else(|| panic!("no compiled radius for {}", sym));
        assert_eq!(got, want, "radius drift for {}", sym);
        count += 1;
    }
    // Every compiled entry must correspond to a json entry (counts match).
    assert_eq!(count, radii::R_COV.len(), "compiled radii count != elements.json");
}

// ----- 6. detect_bonds JSON round-trip ---------------------------------------
#[test]
fn detect_bonds_json_round_trip() {
    let input = br#"[
      {"element": "O", "cart": [0.0, 0.0, 0.0]},
      {"element": "H", "cart": [0.757, 0.586, 0.0]},
      {"element": "H", "cart": [-0.757, 0.586, 0.0]}
    ]"#;
    let out = wyckoff_io::detect_bonds(input).expect("detect_bonds ok");
    let bonds: Vec<[usize; 2]> = serde_json::from_slice(&out).expect("valid JSON");
    assert_eq!(bonds, vec![[0, 1], [0, 2]]);
}

// ----- 7. xyz record fill + supercell caveat ---------------------------------
const WATER_XYZ: &str = "3
water molecule
O  0.000  0.000  0.000
H  0.757  0.586  0.000
H -0.757  0.586  0.000
";

const SI_EXTXYZ: &str = "2
Lattice=\"3.0 0.0 0.0 0.0 3.0 0.0 0.0 0.0 3.0\" Properties=species:S:1:pos:R:3
Si 0.0 0.0 0.0
Si 1.5 1.5 1.5
";

#[test]
fn molecule_record_carries_bonds() {
    let r = wyckoff_io::xyz::parse(WATER_XYZ).unwrap();
    assert_eq!(r.bonds, Some(vec![[0, 1], [0, 2]]));
}

#[test]
fn periodic_record_leaves_bonds_none() {
    // Supercell caveat: imported bonds index the unit-cell atom set, so a
    // periodic (extended-xyz) record must NOT precompute them.
    let r = wyckoff_io::xyz::parse(SI_EXTXYZ).unwrap();
    assert_eq!(r.bonds, None);
}
