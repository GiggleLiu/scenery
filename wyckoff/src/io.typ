// Host-agnostic parsing bridge: loads the wyckoff-io WASM plugin and turns
// its JSON records into wyckoff structures. Path is resolved relative to this
// file so it works under any compilation root.
#import "structure.typ": structure

#let _io = plugin("../plugin/wyckoff_io.wasm")

/// Plugin version string (smoke check that the binary loads).
#let plugin-version() = str(_io.version())

/// Turn a decoded plugin record into a wyckoff structure.
/// No lattice -> molecule (Cartesian atoms); lattice present -> explicit periodic.
/// Note: plain-xyz atoms carry only `cart` (no `frac` key), so the molecule
/// branch reads `a.cart`; extended-xyz atoms carry `frac`, read by the periodic branch.
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
  let record = json(_io.parse_xyz(raw))
  record-to-structure(record)
}
