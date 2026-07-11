#import "/src/scene.typ": sphere, seg, edge, arrow, face, label, build-scene
#import "/src/shape.typ": uv-sphere, cylinder
#import "/src/camera.typ": camera
#import "/src/render.typ": sort-prims, render-scene, _sphere-fill

// A camera with azimuth = elevation = 0 projects (x, y, z) to
// (sx: x, sy: z, depth: y): the depth key is simply the y coordinate. That
// makes the expected sort order exact and hand-checkable.
#let cam0 = camera(azimuth: 0deg, elevation: 0deg)

// --- documented 4-primitive overlapping scene --------------------------------
// All four overlap around the screen origin (x, z in [-1, 1]); they differ only
// in depth (y). Depth keys, worked by hand:
//   edge   midpoint (0, -1, 0) -> depth -1   (farthest)
//   face   centroid (0,  1, 0) -> depth  1
//   seg    midpoint (0,  3, 0) -> depth  3
//   sphere centre   (0,  5, 0) -> depth  5   (nearest)
// Depth grows toward the viewer, so back-to-front (ascending) order is
// edge, face, seg, sphere.
#let p-edge = edge((0, -1, -1), (0, -1, 1))
#let p-face = face(((-1, 1, -1), (1, 1, -1), (0, 1, 1)))
#let p-seg = seg((0, 3, -1), (0, 3, 1))
#let p-sphere = sphere((0, 5, 0), 1)

#let sc = build-scene(p-edge, p-face, p-seg, p-sphere)
#let ordered = sort-prims(sc.prims, cam0)
#assert(ordered.len() == 4, message: "expected 4 prims, got " + str(ordered.len()))
#assert(
  ordered.map(p => p.kind) == ("edge", "face", "seg", "sphere"),
  message: "wrong sort order: " + repr(ordered.map(p => p.kind)),
)
// depth keys are strictly increasing far-to-near (the comparator has teeth)
#for i in range(1, ordered.len()) {
  assert(
    ordered.at(i).depth > ordered.at(i - 1).depth,
    message: "depths not strictly ascending: " + repr(ordered.map(p => p.depth)),
  )
}

// --- shuffled input yields the identical order -------------------------------
// Same four primitives, constructed in a scrambled order: sorting must recover
// the same back-to-front sequence.
#let shuffled = build-scene(p-sphere, p-seg, p-edge, p-face)
#assert(
  sort-prims(shuffled.prims, cam0).map(p => p.kind) == ("edge", "face", "seg", "sphere"),
  message: "shuffled input sorted differently: "
    + repr(sort-prims(shuffled.prims, cam0).map(p => p.kind)),
)

// --- labels always paint last (on top) ---------------------------------------
// A label keeps the +1e9 depth key even against a very near sphere.
#let lsc = build-scene(sphere((0, 100, 0), 1), label((0, 0, 0), [L]))
#assert(sort-prims(lsc.prims, cam0).last().kind == "label", message: "label must sort last")

// --- meshes explode into independently-sorted per-face primitives ------------
// A 6-sided capped cylinder has 6 + 2 = 8 faces; each becomes its own face prim.
#let msc = build-scene(cylinder((0, 0, 0), (0, 0, 2), 1, segments: 6))
#let mordered = sort-prims(msc.prims, cam0)
#assert(mordered.len() == 8, message: "mesh should explode to 8 faces, got " + str(mordered.len()))
#assert(mordered.all(p => p.kind == "face"), message: "exploded mesh faces must all be `face`")

// --- sphere-fill colour-mix guard (the CeTZ 0.5.2 weighting gotcha) -----------
// The sphere body tint must be color.mix((white, 45%), (col, 55%)), NOT the
// mis-weighted white.mix((col, 55%)) (which renormalises to a paler tone).
#let col = rgb("#c44e52")
#assert(
  _sphere-fill(col) == color.mix((white, 45%), (col, 55%)),
  message: "sphere fill uses the wrong color.mix weighting",
)
#assert(
  _sphere-fill(col) != white.mix((col, 55%)),
  message: "sphere fill regressed to the white.mix(..) mis-weighting",
)

Render sort OK

// --- content-level compile test ----------------------------------------------
// A demo scene exercising every draw branch (sphere grid, mesh, segments, edge,
// arrow, face, label) rendered through the full cetz backend. Compiling this
// file at all is the assertion.
#let grid = range(3).map(i => range(3).map(j => sphere((i, j, 0), 0.35, color: blue))).flatten()
#let demo = build-scene(
  grid,
  cylinder((0, 0, 1), (2, 2, 1), 0.3, color: orange),
  seg((0, 0, 0), (2, 2, 0), color: red),
  edge((0, 2, 0), (2, 0, 0)),
  arrow((1, 1, 0), (1, 1, 2), color: purple),
  face(((0, 0, 0.5), (2, 0, 0.5), (2, 2, 0.5), (0, 2, 0.5)), color: green),
  label((1, 1, 2.2), [top]),
)
#render-scene(demo, camera(), width: 6cm)
