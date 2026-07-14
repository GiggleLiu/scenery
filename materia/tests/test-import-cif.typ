#import "/src/io.typ": import-cif

#let close(p, q) = range(3).all(i => {
  let d = calc.abs(p.at(i) - q.at(i))
  calc.min(d, calc.abs(d - 1.0)) < 1e-6
})

// Sub-path 1: explicit op loop, expanded in Rust.
#let a = import-cif(path("/examples/data/nacl-ops.cif"))
#assert.eq(a.kind, "3d")
#assert.eq(a.periodic, (true, true, true))
#assert.eq(a.atoms.len(), 8)
#assert.eq(a.vectors.at(0), (5.64, 0.0, 0.0))
#assert.eq(a.atoms.filter(x => x.element == "Na").len(), 4)
#assert.eq(a.atoms.filter(x => x.element == "Cl").len(), 4)
#assert(a.atoms.any(x => x.element == "Cl" and close(x.frac, (0.5, 0.5, 0.5))),
  message: "op-loop path: Cl at cell center missing")

// Sub-path 2: spacegroup identifier, expanded through materia's tables.
#let b = import-cif(path("/examples/data/nacl-sg.cif"))
#assert.eq(b.kind, "3d")
#assert.eq(b.atoms.len(), 8)

// THE GATE: the two sub-paths must produce the same atom set.
#for atom in a.atoms {
  assert(b.atoms.any(x => x.element == atom.element and close(x.frac, atom.frac)),
    message: "CIF sub-paths disagree: no " + atom.element + " at " + repr(atom.frac))
}
CIF import OK
