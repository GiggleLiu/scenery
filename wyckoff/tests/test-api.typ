#import "/lib.typ": structure, crystal, crystal-group
#import "@preview/cetz:0.5.2"

#let nacl = structure(
  spacegroup: 225, lattice: (a: 5.64),
  sites: ((element: "Na", wyckoff: "a"), (element: "Cl", wyckoff: "b")),
)
#crystal(nacl, colors: (Na: rgb("#4477aa"),), width: 6cm)

// composition: crystal inside a user canvas with an annotation
#cetz.canvas(length: 1cm, {
  import cetz.draw: *
  crystal-group(nacl, colors: (Na: rgb("#4477aa"),), scale: 0.5)
  content((3, -1.5), [conventional cell of NaCl])
})
