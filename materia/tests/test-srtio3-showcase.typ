// Scientific and data-shape contracts for examples/srtio3-introduction.typ.
// Import the example's actual values so the test cannot drift from the figure.
#import "/examples/srtio3-introduction.typ": srtio3, unit-scene, lattice
#import "/examples/srtio3-introduction.typ": path, samples, axis, bands, vb-1, cb-1
#import "/lib.typ": reciprocal-vectors, bz-cell, bz-scene

#assert(srtio3.atoms.len() == 5)
#assert(srtio3.group.number == 221)
#assert(unit-scene.prims.len() > 0)

#assert(axis.k-dists.len() == (path.len() - 1) * samples + 1)
#assert(axis.ticks.labels == path)

#let zone = bz-cell(reciprocal-vectors(lattice))
#assert(zone.vertices.len() == 8)
#assert(zone.faces.len() == 6)
#assert(bz-scene(lattice, bravais: "cP", path: path).prims.len() > 0)

#assert(bands.all(band => band.len() == axis.k-dists.len()))

#let gamma-index = 0
#let r-index = 4 * samples
#let vbm = calc.max(..vb-1)
#let cbm = calc.min(..cb-1)

#assert(calc.abs(vb-1.at(r-index) - vbm) < 1e-8)
#assert(calc.abs(cb-1.at(gamma-index) - cbm) < 1e-8)
#assert(calc.abs((cbm - vbm) - 3.25) < 1e-8)
#assert(calc.abs((cb-1.at(gamma-index) - vb-1.at(gamma-index)) - 3.75) < 1e-8)

[SrTiO3 showcase contracts OK]
