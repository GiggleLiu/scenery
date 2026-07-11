#import "/src/structure.typ": structure, check-site
#import "/src/data.typ": group-data

// wyckoff-input path
#let nacl = structure(
  spacegroup: 225,
  lattice: (a: 5.64),
  sites: ((element: "Na", wyckoff: "a"), (element: "Cl", wyckoff: "b")),
)
#assert(nacl.kind == "3d" and nacl.atoms.len() == 8)
#assert(nacl.group.symbol == "Fm-3m")
#let cl = nacl.atoms.filter(a => a.element == "Cl").first()
#assert(cl.cart.len() == 3)

// free parameters via named args
#let rutile = structure(
  spacegroup: 136,
  lattice: (a: 4.59, c: 2.96),
  sites: ((element: "Ti", wyckoff: "a"), (element: "O", wyckoff: "f", x: 0.305)),
)
#assert(rutile.atoms.len() == 6)

// layer group
#let mos2 = structure(
  layergroup: 78,
  lattice: (a: 3.16),
  sites: (
    (element: "Mo", wyckoff: "a"),
    (element: "S", wyckoff: "f", z: 1.56),
  ),
)
#assert(mos2.kind == "layer" and mos2.periodic == (true, true, false))
#assert(mos2.atoms.len() == 3)
#assert(mos2.atoms.filter(a => a.element == "S").all(a => calc.abs(calc.abs(a.cart.at(2)) - 1.56) < 1e-6))

// explicit lattice + basis
#let sto = structure(
  lattice: ((3.9, 0, 0), (0, 3.9, 0), (0, 0, 3.9)),
  atoms: (("Sr", (0.5, 0.5, 0.5)), ("Ti", (0, 0, 0)),
          ("O", (0.5, 0, 0)), ("O", (0, 0.5, 0)), ("O", (0, 0, 0.5))),
)
#assert(sto.group == none and sto.atoms.len() == 5)

// validation surfaces good messages (pure checker)
#let g = group-data("3d", 136)
#assert(not check-site(g, (element: "O", wyckoff: "f")).ok, message: "136f needs x")
#assert(not check-site(g, (element: "O", wyckoff: "f", x: 0.3, y: 0.1)).ok, message: "y is not free on 136f")
#assert(not check-site(g, (element: "O", wyckoff: "q", x: 0.3)).ok, message: "no such letter")
#assert(check-site(g, (element: "O", wyckoff: "f", x: 0.305)).ok)
Structure OK
