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
// Two O-H bonds; build-scene splits each into two colour halves (two-tone),
// so 2 bonds -> 4 "seg" primitives.
#assert(prims.filter(p => p.kind == "seg").len() == 4, message: "2 O-H bonds (two-tone -> 4 segs)")
