#import "/src/io.typ": _io, import-xyz
#import "/src/real/geometry.typ": find-bonds, display-atoms
#import "/src/core/structure.typ": structure
#import "/src/real/figure.typ": crystal-scene

// ===== Rust/Typst bond-equivalence gate (design doc, "Testing & gates") =====
// Same rule, same radii source: the two implementations must agree exactly.

// 1. Imported molecule: the parser-precomputed bonds equal Typst find-bonds.
#let water = import-xyz(path("/examples/data/water.xyz"))
#assert.eq(water.bonds, ((0, 1), (0, 2)))
#let shown = display-atoms(water)
#assert.eq(water.bonds.map(b => (i: b.at(0), j: b.at(1))), find-bonds(shown, auto))

// 2. detect_bonds on a PERIODIC displayed set (boundary images included) --
// the render-time accelerator path must match Typst on the same atom list.
#let nacl = structure(spacegroup: 225, lattice: (a: 5.64),
  sites: ((element: "Na", wyckoff: "a"), (element: "Cl", wyckoff: "b")))
#let shown2 = display-atoms(nacl)
#let rust2 = json(_io.detect_bonds(bytes(json.encode(
  shown2.map(a => (element: a.element, cart: a.cart))))))
#assert.eq(rust2.map(b => (i: b.at(0), j: b.at(1))), find-bonds(shown2, auto))

// 3. Benzene count pin (12 bonds), through detect_bonds.
#let ring(el, r) = range(6).map(k =>
  (element: el, cart: (r * calc.cos(k * 60deg), r * calc.sin(k * 60deg), 0.0)))
#let rust3 = json(_io.detect_bonds(bytes(json.encode(ring("C", 1.39) + ring("H", 2.48)))))
#assert.eq(rust3.len(), 12)

// 4. The molecule figure is UNCHANGED by precomputed bonds: same prims as a
// hand-built structure without them (the bond sets are equal, so the scene is).
#let hand = structure(atoms: water.atoms.map(a => (a.element, a.cart)))
#assert.eq(crystal-scene(water).prims, crystal-scene(hand).prims)

// 5. engine="wasm" bond path: identical scene to the pure path (the render-time
// detect_bonds accelerator equivalence lifted to the figure level).
#assert.eq(crystal-scene(nacl, engine: "wasm").prims, crystal-scene(nacl).prims)

Bonds OK
