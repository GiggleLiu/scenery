#import "/src/structure.typ": structure
#import "/src/figure.typ": build-scene, occlude, render

#let nacl = structure(
  spacegroup: 225, lattice: (a: 5.64),
  sites: ((element: "Na", wyckoff: "a"), (element: "Cl", wyckoff: "b")),
)

// Orthographic scenes are UNCHANGED by the perspective plumbing: an explicit
// orthographic view is prim-for-prim and bbox-for-bbox equal to the default.
#let v = (azimuth: 30deg, elevation: 15deg)
#let plain = build-scene(nacl, view: v)
#let explicit = build-scene(nacl, view: (..v, mode: "orthographic"))
#assert.eq(plain.prims, explicit.prims)
#assert.eq(plain.bbox, explicit.bbox)
#assert.eq(plain.camera, (mode: "orthographic", azimuth: 30deg, elevation: 15deg))

// Perspective camera is threaded through the view dict.
#let pv = (azimuth: 30deg, elevation: 15deg, mode: "perspective", distance: 20.0)
#let per = build-scene(nacl, view: pv)
#assert.eq(per.camera.mode, "perspective")
#assert.eq(per.camera.distance, 20.0)

// World-space primitives are IDENTICAL (radii stay world radii; perspective
// enters only at projection time: bbox, occlude, and the renderer).
#assert.eq(per.prims, plain.prims)

// The screen bbox is not: near-side magnification widens it.
#assert(per.bbox.at(2) - per.bbox.at(0) > plain.bbox.at(2) - plain.bbox.at(0),
  message: "perspective must widen the screen bbox (near side magnified)")

// occlude() still suppresses covered bond stubs under perspective (the
// coverage heuristic runs on self-consistent screen quantities).
#let kept = occlude(per.prims, per.camera)
#assert(kept.filter(p => p.kind == "seg").len() < per.prims.filter(p => p.kind == "seg").len(),
  message: "coverage suppression must still fire under perspective")
// ... and is bit-for-bit unchanged for the orthographic scene.
#assert.eq(occlude(plain.prims, plain.camera), occlude(explicit.prims, explicit.camera))

// End-to-end compile smoke: a perspective figure renders.
#render(per, width: 6cm, legend: false)
