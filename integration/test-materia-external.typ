#import "@preview/materia:0.1.0": import-xyz

// This path is rooted at the caller, outside the package. It guards the Typst
// 0.15 cross-package path behavior that materia's file API relies on.
#let source = path("data/water.xyz")
#let water = import-xyz(source)
#assert.eq(water.kind, "molecule")
#assert.eq(water.atoms.len(), 3)

// Already-loaded bytes are the package-boundary alternative for generated data.
#let from-bytes = import-xyz(read(source, encoding: none))
#assert.eq(from-bytes.atoms, water.atoms)

External materia path import OK
