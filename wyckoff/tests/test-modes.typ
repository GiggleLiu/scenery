#import "/src/structure.typ": structure
#import "/src/figure.typ": build-scene
#import "/src/data.typ": element-info

// Water: 3 atoms, 2 O-H bonds (find-bonds covalent rule; pinned by
// test-molecule.typ as 4 two-tone segs).
#let water = structure(atoms: (
  ("O", (0.0, 0.0, 0.0)),
  ("H", (0.757, 0.586, 0.0)),
  ("H", (-0.757, 0.586, 0.0)),
))

// THE BALL-AND-STICK GATE AT DATA LEVEL: the default output must be exactly
// equal to an explicit mode: "ball-and-stick". (test-scene.typ, untouched,
// additionally pins that this default equals the pre-mode-era output.)
#let default-scene = build-scene(water)
#let bas = build-scene(water, mode: "ball-and-stick")
#assert.eq(default-scene.prims, bas.prims)
#assert.eq(default-scene.bbox, bas.bbox)
// auto radius in ball-and-stick means today's 0.45 x r-atom
#let o-sphere = default-scene.prims.filter(p => p.kind == "sphere").first()
#assert(calc.abs(o-sphere.r - 0.45 * element-info("O").r-atom) < 1e-12)

// space-filling: full vdW spheres, NO bond segs.
#let cpk = build-scene(water, mode: "space-filling")
#let cpk-spheres = cpk.prims.filter(p => p.kind == "sphere")
#assert.eq(cpk-spheres.len(), 3)
#assert.eq(cpk.prims.filter(p => p.kind == "seg").len(), 0,
  message: "space-filling draws no bonds")
#assert(calc.abs(cpk-spheres.at(0).r - element-info("O").r-vdw) < 1e-9)
#assert(calc.abs(cpk-spheres.at(1).r - element-info("H").r-vdw) < 1e-9)
// "cpk" is a pure alias
#assert.eq(build-scene(water, mode: "cpk").prims, cpk.prims)
// a numeric radius scales the vdW spheres
#let cpk-half = build-scene(water, mode: "space-filling", radius: 0.5)
#assert(calc.abs(cpk-half.prims.first().r - 0.5 * element-info("O").r-vdw) < 1e-9)

// licorice: uniform caps at 0.55 x bond-width; untrimmed two-tone sticks.
#let lic = build-scene(water, mode: "licorice")
#let lic-spheres = lic.prims.filter(p => p.kind == "sphere")
#assert(lic-spheres.all(p => calc.abs(p.r - 0.55 * 0.25) < 1e-12),
  message: "licorice caps are element-independent: 0.55 x bond-width")
#let lic-segs = lic.prims.filter(p => p.kind == "seg")
#assert.eq(lic-segs.len(), 4, message: "2 bonds x 2 two-tone halves")
#assert(lic-segs.all(p => calc.abs(p.w - 0.25) < 1e-12))
#assert.eq(lic-segs.first().a, (0.0, 0.0, 0.0),
  message: "licorice bonds are untrimmed: they start at the atom center")

// bond-color opt-out: ONE seg per bond, verbatim color, both relevant modes.
#let single = build-scene(water, bond-color: luma(100))
#let single-segs = single.prims.filter(p => p.kind == "seg")
#assert.eq(single-segs.len(), 2, message: "single-color bonds are not split")
#assert(single-segs.all(p => p.color == luma(100)))
// the single seg spans the same trimmed extent as the two-tone pair
#assert.eq(single-segs.first().a, default-scene.prims.filter(p => p.kind == "seg").first().a)
#assert.eq(single-segs.first().b, default-scene.prims.filter(p => p.kind == "seg").at(1).b)
#let lic-single = build-scene(water, mode: "licorice", bond-color: luma(100))
#assert.eq(lic-single.prims.filter(p => p.kind == "seg").len(), 2)

Modes OK
