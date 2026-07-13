#import "@preview/scenery:0.1.0": camera as _camera, project as _project
#import "/src/structure.typ": structure
#import "/src/figure.typ": build-scene
#import "/src/data.typ": element-info

// Adapter: wyckoff's old `projector(view)` closure over scenery's
// `project(cam, pt)` (the projection convention now lives in the core).
#let projector(view) = p => _project(_camera(
  azimuth: view.at("azimuth", default: 25deg),
  elevation: view.at("elevation", default: 15deg),
), p)

// pin the projection convention
#let p0 = projector((azimuth: 0deg, elevation: 0deg))
#let s = p0((1.0, 0.0, 0.0))
#assert(calc.abs(s.sx - 1.0) < 1e-9 and calc.abs(s.sy) < 1e-9)
#let s = p0((0.0, 0.0, 1.0))
#assert(calc.abs(s.sy - 1.0) < 1e-9 and calc.abs(s.depth) < 1e-9)
#let s = p0((0.0, 1.0, 0.0))
#assert(calc.abs(s.depth - 1.0) < 1e-9, message: "+y toward viewer at az=el=0")
#let top = projector((azimuth: 0deg, elevation: 90deg))((0.0, 0.0, 1.0))
#assert(calc.abs(top.depth - 1.0) < 1e-9, message: "top view: +z toward viewer")

#let nacl = structure(
  spacegroup: 225, lattice: (a: 5.64),
  sites: ((element: "Na", wyckoff: "a"), (element: "Cl", wyckoff: "b")),
)
#let sc = build-scene(nacl, view: (azimuth: 30deg, elevation: 15deg))
#let spheres = sc.prims.filter(p => p.kind == "sphere")
#assert(spheres.len() == 27)
#assert(sc.prims.filter(p => p.kind == "seg").len() == 108, message: "54 bonds x 2 halves")
#assert(sc.prims.filter(p => p.kind == "edge").len() == 96, message: "12 edges x 8 splits")
#assert(sc.elements == ("Na", "Cl"))
#let custom-blue = rgb("#4477aa")
#let custom = build-scene(nacl, colors: (Na: custom-blue,))
#assert(custom.element-colors == (custom-blue, element-info("Cl").color))
#assert(custom.prims.filter(p => p.kind == "sphere" and p.element == "Na").first().color == custom-blue)
#assert(
  custom.prims.filter(p => p.kind == "sphere" and p.element == "Cl").first().color
    == element-info("Cl").color,
  message: "partial color map must retain unspecified element defaults",
)
#assert(custom.prims.filter(p => p.kind == "seg").any(p => p.color == custom-blue.darken(10%)))
#assert(sc.bbox.at(0) < sc.bbox.at(2))
// polyhedra path
#let sto = structure(
  spacegroup: 221, lattice: (a: 3.905),
  sites: ((element: "Sr", wyckoff: "a"), (element: "Ti", wyckoff: "b"), (element: "O", wyckoff: "c")),
)
#let sc2 = build-scene(sto, view: (azimuth: 30deg, elevation: 15deg),
  bonds: ((elements: ("Ti", "O"), max: 2.2),), polyhedra: ("Ti",),
  colors: (Ti: custom-blue,))
#assert(sc2.prims.filter(p => p.kind == "face").len() == 8)
#assert(sc2.prims.filter(p => p.kind == "face").all(p => p.color == custom-blue))
#assert(sc2.prims.filter(p => p.kind == "face").all(p => p.depth-key == "back"),
  message: "coordination faces must sort from their back support point")
Scene OK
