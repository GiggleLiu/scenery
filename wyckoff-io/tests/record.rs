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
