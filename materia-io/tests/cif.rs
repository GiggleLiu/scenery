use materia_io::cif::{self, element_symbol, parse_op};

const NACL_OPS: &str = include_str!("../../materia/examples/data/nacl-ops.cif");
const NACL_SG: &str = include_str!("../../materia/examples/data/nacl-sg.cif");
const NACL_NOSYM: &str = include_str!("../../materia/tests/data/nacl-nosym.cif");

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
fn hm_symbol_is_case_insensitive() {
    // Some CIF exporters upper-case the H-M symbol ('F M -3 M'). The 230-symbol
    // table is unique under ASCII case-folding, so the lookup is case-insensitive.
    let src = NACL_SG.replace("_space_group_IT_number 225", "_symmetry_space_group_name_H-M 'F M -3 M'");
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
