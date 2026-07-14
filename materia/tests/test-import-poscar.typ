#import "/src/io.typ": import-poscar

// Direct-mode POSCAR -> periodic structure.
#let cu = import-poscar(path("/examples/data/cu.poscar"))
#assert.eq(cu.kind, "3d")
#assert.eq(cu.periodic, (true, true, true))
#assert.eq(cu.vectors.at(0), (3.615, 0.0, 0.0))
#assert.eq(cu.atoms.len(), 4)
#assert(cu.atoms.all(a => a.element == "Cu"))
#assert.eq(cu.atoms.at(1).frac, (0.0, 0.5, 0.5))

// Cartesian-mode POSCAR with scale factor -> same NaCl cell as the fixtures.
#let nacl = import-poscar(path("/examples/data/nacl-cart.poscar"))
#assert.eq(nacl.kind, "3d")
#assert.eq(nacl.atoms.len(), 8)
#assert.eq(nacl.atoms.filter(a => a.element == "Na").len(), 4)
#assert.eq(nacl.atoms.filter(a => a.element == "Cl").len(), 4)
#assert.eq(nacl.vectors.at(0), (5.64, 0.0, 0.0))
#let cl = nacl.atoms.at(4)
#assert.eq(cl.element, "Cl")
#assert(range(3).all(i => calc.abs(cl.frac.at(i) - 0.5) < 1e-9), message: "first Cl at (1/2,1/2,1/2)")
POSCAR import OK
