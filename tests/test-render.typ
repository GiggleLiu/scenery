#import "/src/structure.typ": structure
#import "/src/scene.typ": build-scene
#import "/src/render.typ": render

#set page(width: auto, height: auto, margin: 0.5cm)

#let nacl = structure(
  spacegroup: 225, lattice: (a: 5.64),
  sites: ((element: "Na", wyckoff: "a"), (element: "Cl", wyckoff: "b")),
)
#render(build-scene(nacl), width: 8cm)

#pagebreak()
// perovskite with TiO6 octahedra, legend, axes
#let sto = structure(
  spacegroup: 221, lattice: (a: 3.905),
  sites: ((element: "Sr", wyckoff: "a"), (element: "Ti", wyckoff: "b"), (element: "O", wyckoff: "c")),
)
#render(
  build-scene(sto, bonds: ((elements: ("Ti", "O"), max: 2.2),), polyhedra: ("Ti",), labels: true),
  width: 8cm, legend: true, axes-info: (vectors: sto.vectors, view: (azimuth: 25deg, elevation: 15deg)),
)

#pagebreak()
// MoS2 slab: layer group, no c edges
#let mos2 = structure(
  layergroup: 78, lattice: (a: 3.16),
  sites: ((element: "Mo", wyckoff: "b"), (element: "S", wyckoff: "f", z: 1.56)),
)
#render(
  build-scene(mos2, supercell: (4, 4, 1), bonds: ((elements: ("Mo", "S"), max: 2.6),)),
  width: 10cm,
)
