use materia_io::geom::{cart_to_frac, cell_to_vectors, frac_to_cart, wrap01};

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
    // Must match materia/src/core/lattice.typ lattice-vectors: a along +x, b in xy.
    let l = cell_to_vectors(3.0, 3.0, 5.0, 90.0, 90.0, 120.0).unwrap();
    assert!(close(l[0][0], 3.0) && close(l[0][1], 0.0) && close(l[0][2], 0.0));
    assert!(close(l[1][0], -1.5) && close(l[1][1], 3.0 * 0.75f64.sqrt()) && close(l[1][2], 0.0)); // b·sin 120° = 3√3/2
    assert!(close(l[2][0], 0.0) && close(l[2][1], 0.0) && close(l[2][2], 5.0));
}

#[test]
fn cell_to_vectors_triclinic_matches_expected() {
    // Expected values computed INDEPENDENTLY with python3 (standard convention,
    // matching materia/src/core/lattice.typ lattice-vectors) — NOT recomputed inline:
    //   a=3, b=4, c=5, alpha=80°, beta=95°, gamma=110°
    // Pins v3's cross-term cy to a specific nonzero value; a sign error or
    // transposition in cell_to_vectors would fail here.
    let l = cell_to_vectors(3.0, 4.0, 5.0, 80.0, 95.0, 110.0).unwrap();
    let expected = [
        [3.0, 0.0, 0.0],
        [-1.3680805733026749, 3.7587704831436337, 0.0],
        [-0.4357787137382912, 0.765352173992927, 4.9218221181201685],
    ];
    for i in 0..3 {
        for j in 0..3 {
            assert!(close(l[i][j], expected[i][j]), "l[{}][{}] = {} != {}", i, j, l[i][j], expected[i][j]);
        }
    }
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
