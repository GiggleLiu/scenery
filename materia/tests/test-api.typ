#import "/lib.typ": structure, crystal, crystal-scene
#import "/lib.typ" as materia
#import "@preview/scenery:0.1.0" as scenery
#import "@preview/cetz:0.5.2"

#let nacl = structure(
  spacegroup: 225, lattice: (a: 5.64),
  sites: ((element: "Na", wyckoff: "a"), (element: "Cl", wyckoff: "b")),
)
#crystal(nacl, colors: (Na: rgb("#4477aa"),), width: 6cm)

// Specialist namespaces and stable scene constructors are public.
#assert(type(materia.core.structure) == function)
#assert(type(materia.real.crystal-scene) == function)
#assert(type(materia.reciprocal.bz-scene) == function)
#assert(type(materia.electronic.mo-scene) == function)
#let bz = materia.bz-scene((a: 3.61), bravais: "cF", kpath: false)
#assert("prims" in bz and "bbox" in bz)

// composition: crystal inside a user canvas with an annotation
#cetz.canvas(length: 1cm, {
  import cetz.draw: *
  let scene = crystal-scene(nacl, colors: (Na: rgb("#4477aa"),))
  scenery.scene-group(scene, scene.camera, unit: 0.5)
  content((3, -1.5), [conventional cell of NaCl])
})
