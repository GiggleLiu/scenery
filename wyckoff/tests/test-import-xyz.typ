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
