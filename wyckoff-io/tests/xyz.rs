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
