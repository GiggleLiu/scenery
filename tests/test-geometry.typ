#import "/src/structure.typ": structure
#import "/src/geometry.typ": display-atoms, cell-edges

#let nacl = structure(
  spacegroup: 225,
  lattice: (a: 5.64),
  sites: ((element: "Na", wyckoff: "a"), (element: "Cl", wyckoff: "b")),
)

// textbook rocksalt cell: 14 Na (8 corners + 6 faces) + 13 Cl (12 edges + 1 center)
#let shown = display-atoms(nacl)
#assert(shown.len() == 27, message: "got " + str(shown.len()))
#assert(shown.filter(a => a.element == "Na").len() == 14)
#assert(shown.filter(a => a.element == "Cl").len() == 13)

// no boundary duplication when disabled
#assert(display-atoms(nacl, boundary: false).len() == 8)

// 2x1x1 supercell Na count.
// Ground truth (derived on paper, NOT fit to code): count the fcc Na lattice
// points lying on the closed doubled box [0,2] x [0,1] x [0,1]. An fcc point has
// each coordinate in {integer, half-integer} with an EVEN number (0 or 2) of
// half-integer coordinates.
//   * 0 half-integers (corner/integer points): x in {0,1,2}, y in {0,1}, z in {0,1}
//       = 3 * 2 * 2 = 12
//   * 2 half-integers:
//       - x,y half, z int:  x in {0.5,1.5}, y in {0.5}, z in {0,1} = 2*1*2 = 4
//       - x,z half, y int:  x in {0.5,1.5}, z in {0.5}, y in {0,1} = 2*1*2 = 4
//       - y,z half, x int:  y in {0.5}, z in {0.5}, x in {0,1,2}   = 1*1*3 = 3
//       subtotal = 11
//   total = 12 + 11 = 23
// Cross-check: two textbook cubes (14 Na each) share the x=1 face, which holds
// 4 corners + 1 face-center = 5 Na. 14 + 14 - 5 = 23.
// (The brief's printed "21" undercounts the x,y-/x,z-half families by 2; corrected here.)
#let sc = display-atoms(nacl, supercell: (2, 1, 1))
#assert(sc.filter(a => a.element == "Na").len() == 23, message: "got " + str(sc.filter(a => a.element == "Na").len()))
#assert(cell-edges(nacl).len() == 12)
#assert(cell-edges(nacl, supercell: (2, 1, 1)).len() == 20, message: "two cubes sharing a face: 24 - 4 shared")

// explicit atom on a periodic face gains a boundary partner on the opposite face:
// (1.0, 0.5, 0.5) must yield a partner at (0.0, 0.5, 0.5).
#let onface = structure(
  lattice: ((4.0, 0, 0), (0, 4.0, 0), (0, 0, 4.0)),
  atoms: (("Fe", (1.0, 0.5, 0.5)),),
)
#let of = display-atoms(onface)
#assert( of.any(a => calc.abs(a.frac.at(0) - 0.0) < 1e-6
  and calc.abs(a.frac.at(1) - 0.5) < 1e-6
  and calc.abs(a.frac.at(2) - 0.5) < 1e-6),
  message: "expected boundary partner at (0.0, 0.5, 0.5)")

// layer structure: cell drawn as 4 in-plane edges.
// (Uses Wyckoff "f", the mult-2 z-free position of layergroup 78; the brief's
// "h" has free vars x,y and would reject a z: argument at construction.)
#let mos2 = structure(
  layergroup: 78, lattice: (a: 3.16),
  sites: ((element: "Mo", wyckoff: "a"), (element: "S", wyckoff: "f", z: 1.56)),
)
#assert(cell-edges(mos2).len() == 4)
Geometry OK

#import "/src/geometry.typ": find-bonds

// NaCl textbook cell: 54 Na-Cl bonds among the 27 displayed atoms
// (center Cl -> 6 face Na; each of 12 edge Cl -> 2 corner + 2 face Na)
#let bonds = find-bonds(shown, auto)
#assert(bonds.len() == 54, message: "got " + str(bonds.len()))
#for b in bonds {
  assert(shown.at(b.i).element != shown.at(b.j).element, message: "auto rule: no Na-Na/Cl-Cl at 2.82A")
}

// explicit rules: forbid everything except an impossible pair -> no bonds
#assert(find-bonds(shown, ((elements: ("Na", "Na"), max: 1.0),)).len() == 0)
// explicit Na-Cl cutoff
#assert(find-bonds(shown, ((elements: ("Na", "Cl"), max: 2.9),)).len() == 54)
Bonds OK

#import "/src/geometry.typ": find-polyhedra

#let sto = structure(
  spacegroup: 221, lattice: (a: 3.905),
  sites: ((element: "Sr", wyckoff: "a"), (element: "Ti", wyckoff: "b"), (element: "O", wyckoff: "c")),
)
#let sshown = display-atoms(sto)
#let sbonds = find-bonds(sshown, ((elements: ("Ti", "O"), max: 2.2),))
#let polys = find-polyhedra(sshown, sbonds, ("Ti",))
// exactly one Ti displayed (cell center), octahedrally coordinated
#assert(polys.len() == 1, message: "got " + str(polys.len()))
#assert(polys.first().faces.len() == 8, message: "octahedron has 8 faces, got " + str(polys.first().faces.len()))
#assert(polys.first().faces.all(f => f.len() == 3))
Polyhedra OK
