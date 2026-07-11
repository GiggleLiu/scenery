#import "/src/structure.typ": structure
#import "/src/scene.typ": build-scene
#import "/src/render.typ": render

#set page(width: auto, height: auto, margin: 0.5cm)

#let nacl = structure(
  spacegroup: 225, lattice: (a: 5.64),
  sites: ((element: "Na", wyckoff: "a"), (element: "Cl", wyckoff: "b")),
)
#render(build-scene(nacl), width: 8cm)
