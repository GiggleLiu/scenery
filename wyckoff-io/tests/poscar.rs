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
