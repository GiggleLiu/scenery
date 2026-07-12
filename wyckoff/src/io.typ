// Host-agnostic parsing bridge: loads the wyckoff-io WASM plugin and turns
// its JSON records into wyckoff structures. Path is resolved relative to this
// file so it works under any compilation root.
#import "structure.typ": structure
#import "data.typ": group-data
#import "symmetry.typ": expand-general

#let _io = plugin("../plugin/wyckoff_io.wasm")

/// Plugin version string (smoke check that the binary loads).
#let plugin-version() = str(_io.version())

/// Turn a decoded plugin record into a wyckoff structure.
/// - no lattice            -> molecule (Cartesian atoms)
/// - lattice + spacegroup  -> CIF identifier path: expand the asymmetric unit
///                            through wyckoff's spacegroup tables, then build
///                            an explicit periodic structure
/// - lattice, no spacegroup -> explicit periodic (atoms carry frac)
/// Note: plain-xyz atoms carry only `cart` (no `frac` key), so the molecule
/// branch reads `a.cart`; extended-xyz atoms carry `frac`, read by the periodic branch.
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

/// Read an .xyz / extended-xyz file and return a renderable structure.
#let import-xyz(path) = {
  let raw = read(path, encoding: none)   // bytes
  let record = json(_io.parse_xyz(raw))
  record-to-structure(record)
}

/// Read a VASP 5 POSCAR/CONTCAR file and return a periodic structure.
/// Direct and Cartesian coordinate modes are supported; the scale factor is
/// applied to the lattice (and, per VASP semantics, to Cartesian positions).
#let import-poscar(path) = {
  let raw = read(path, encoding: none)   // bytes
  let record = json(_io.parse_poscar(raw))
  record-to-structure(record)
}

/// Read a CIF file (pragmatic subset) and return a periodic structure.
/// Symmetry: an explicit op loop is applied by the plugin; a bare spacegroup
/// identifier is expanded here through wyckoff's tables; files with neither
/// are rejected with an error naming the missing tags.
#let import-cif(path) = {
  let raw = read(path, encoding: none)   // bytes
  let record = json(_io.parse_cif(raw))
  record-to-structure(record)
}
