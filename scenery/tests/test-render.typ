#import "/src/scene.typ": sphere, seg, edge, arrow, face, mesh, label, build-scene
#import "/src/shape.typ": uv-sphere, cylinder
#import "/src/camera.typ": camera
#import "/src/style.typ": default-theme
#import "/src/render.typ": sort-prims, scene-group, render-scene, _sphere-fill, _sphere-gradient, _clip-lines, _prepare-faces, _record, _projected-sphere
#import "@preview/cetz:0.5.2"

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

// --- selectable depth key for intersecting primitives ----------------------
// A coordination face can overlap an opaque ligand sphere. Its centroid can be
// nearer than the sphere even though one vertex extends behind it, causing the
// whole translucent triangle to overpaint the atom. `back` anchors the face at
// its farthest support point; `front` provides the dual policy. The default
// remains the historical centroid key.
#let shared-sphere = sphere((0, 0, 0), 1)
#let crossing-default = face(((-1, -2, -1), (1, 2, -1), (0, 2, 1)))
#let crossing-back = face(crossing-default.pts, depth-key: "back")
#let crossing-front = face(crossing-default.pts, depth-key: "front")
#assert.eq(sort-prims((shared-sphere, crossing-default), cam0).map(p => p.kind), ("sphere", "face"))
#assert.eq(sort-prims((shared-sphere, crossing-back), cam0).map(p => p.kind), ("face", "sphere"))
#assert.eq(sort-prims((shared-sphere, crossing-front), cam0).map(p => p.kind), ("sphere", "face"))
#assert.eq(sort-prims((crossing-back,), cam0).first().depth, -2)
#assert.eq(sort-prims((crossing-front,), cam0).first().depth, 2)

// Exact shared support points still tie: stable input order decides which one
// paints last. Callers that need a guaranteed order at a shared vertex must add
// a small depth offset (the Wyckoff polyhedron builder does this).
#let tied-face = face(((0, 0, 0), (1, 2, -1), (0, 2, 1)), depth-key: "back")
#assert.eq(sort-prims((shared-sphere, tied-face), cam0).map(p => p.kind), ("sphere", "face"))
#assert.eq(sort-prims((tied-face, shared-sphere), cam0).map(p => p.kind), ("face", "sphere"))

// --- labels always paint last (on top) ---------------------------------------
// A label keeps the +1e9 depth key even against a very near sphere.
#let lsc = build-scene(sphere((0, 100, 0), 1), label((0, 0, 0), [L]))
#assert(sort-prims(lsc.prims, cam0).last().kind == "label", message: "label must sort last")

// --- line/sphere visibility -------------------------------------------------
// Lines are clipped only where an opaque sphere is actually in front. This is
// prepared separately from sort-prims so its public sorting contract is stable.
#let clipped-bond = _clip-lines(
  (sphere((0, 0, 0), 1), seg((0, 0, 0), (2, 0, 0))), cam0,
)
#let bond-parts = clipped-bond.filter(p => p.kind == "seg")
#assert(bond-parts.len() == 1, message: "center bond should leave one visible fragment")
#assert(
  calc.abs(bond-parts.first().a.at(0) - 1.0) < 1e-6,
  message: "bond must begin at the sphere silhouette, got " + repr(bond-parts.first().a),
)

// A rear line entirely inside the projected disk is fully hidden.
#let rear = _clip-lines(
  (sphere((0, 0, 0), 1), edge((-0.5, -2, 0), (0.5, -2, 0))), cam0,
)
#assert(rear.filter(p => p.kind == "edge").len() == 0, message: "rear line leaked through sphere")

// A line nearer than the sphere's front surface stays visible.
#let front = _clip-lines(
  (sphere((0, 0, 0), 1), edge((-0.5, 2, 0), (0.5, 2, 0))), cam0,
)
#assert(front.filter(p => p.kind == "edge").len() == 1, message: "foreground line was hidden")

// Edge dash styling reaches the draw record (used by scientific correlation
// diagrams while keeping the primitive itself renderer-agnostic).
#let dashed = _record(cam0, 1, default-theme, edge((0, 0, 0), (1, 0, 0), dash: "dashed"))
#assert.eq(dashed.stroke.dash, "dashed")

// A sloped-depth line can leave the projected disk before it passes behind the
// sphere. The overlapping foreground piece needs its own depth key; otherwise
// the distant tail's midpoint would incorrectly place the whole line behind.
#let crossing = _clip-lines(
  (sphere((0, 0, 0), 1), edge((0, 2, 0), (4, -4, 0))), cam0,
)
#let crossing-parts = crossing.filter(p => p.kind == "edge")
#assert(crossing-parts.len() == 2, message: "sphere boundary must split visible depth crossing")
#let crossing-ordered = sort-prims(crossing, cam0)
#assert(
  crossing-ordered.last().kind == "edge" and crossing-ordered.last().depth > 0,
  message: "valid foreground crossing must paint after the sphere",
)

// Geometry is scale-invariant: tiny coordinates must clip to the same relative
// silhouette instead of being mistaken for a degenerate constant line.
#let tiny = _clip-lines(
  (sphere((0, 0, 0), 1e-6), seg((0, 0, 0), (2e-6, 0, 0))), cam0,
)
#let tiny-parts = tiny.filter(p => p.kind == "seg")
#assert(tiny-parts.len() == 1, message: "tiny bond should retain its outer half")
#assert(
  calc.abs(tiny-parts.first().a.at(0) - 1e-6) < 1e-12,
  message: "tiny bond clipped at the wrong scale",
)

// Two disjoint sphere silhouettes split one line into three visible fragments.
#let multi = _clip-lines(
  (
    sphere((-1, 0, 0), 0.5), sphere((1, 0, 0), 0.5),
    seg((-3, 0, 0), (3, 0, 0)),
  ),
  cam0,
)
#assert(
  multi.filter(p => p.kind == "seg").len() == 3,
  message: "two spheres should split a line into three fragments",
)

// Arrows share the exact line/sphere visibility path. Only the terminal visible
// fragment keeps the mark, so splitting never duplicates an arrowhead.
#let clipped-arrow = _clip-lines(
  (sphere((0, 0, 0), 1), arrow((-2, 0, 0), (2, 0, 0))), cam0,
)
#let arrow-parts = clipped-arrow.filter(p => p.kind == "arrow")
#assert(arrow-parts.len() == 2, message: "sphere must split a crossing arrow")
#assert(
  not arrow-parts.first().draw-head and arrow-parts.last().draw-head,
  message: "only the terminal arrow fragment may retain its head",
)
#let hidden-tip = _clip-lines(
  (sphere((0, 0, 0), 1), arrow((-2, 0, 0), (0, 0, 0))), cam0,
).filter(p => p.kind == "arrow")
#assert(hidden-tip.len() == 1 and not hidden-tip.first().draw-head,
  message: "an occluded arrow tip must not leave a floating head")

// Multiple disjoint occluders produce multiple shaft fragments, still with one
// terminal head. A distant sphere exercises the broad-phase rejection path and
// must leave geometry byte-for-byte equivalent to the no-sphere case.
#let multi-arrow = _clip-lines(
  (
    sphere((-1, 0, 0), 0.5), sphere((1, 0, 0), 0.5),
    arrow((-3, 0, 0), (3, 0, 0)),
  ), cam0,
).filter(p => p.kind == "arrow")
#assert(multi-arrow.len() == 3)
#assert(multi-arrow.filter(p => p.draw-head).len() == 1 and multi-arrow.last().draw-head)
#let bare-arrow = _clip-lines((arrow((-2, 0, 0), (2, 0, 0)),), cam0)
#let broad-phase-arrow = _clip-lines(
  (sphere((100, 0, 100), 1), arrow((-2, 0, 0), (2, 0, 0))), cam0,
).filter(p => p.kind == "arrow")
#assert(broad-phase-arrow == bare-arrow,
  message: "broad-phase rejection must preserve an unrelated arrow exactly")

// An opaque planar face hides only the portion of a changing-depth line that
// lies both inside its projection and behind its plane. Under cam0, depth == y.
#let screen-face = face(
  ((-1, 0, -1), (1, 0, -1), (1, 0, 1), (-1, 0, 1)),
  fill-opacity: 0%,
)
#let face-crossing = _clip-lines(
  (screen-face, seg((-2, -1, 0), (2, 1, 0))), cam0,
).filter(p => p.kind == "seg")
#assert(face-crossing.len() == 3,
  message: "opaque face must remove only the rear projected interval")
#assert(calc.abs(face-crossing.first().b.at(0) + 1) < 1e-9)
#assert(calc.abs(face-crossing.at(1).a.at(0)) < 1e-9)
#assert(face-crossing.last().b == (2, 1, 0))

// Face visibility is unit-invariant. The same geometry at micro and mega scale
// must retain the same fragment topology and normalized cut positions.
#for scale in (1e-6, 1e6) {
  let scaled(p) = p.map(x => x * scale)
  let tiny-or-large = _clip-lines(
    (
      face(screen-face.pts.map(scaled), fill-opacity: 0%),
      seg(scaled((-2, -1, 0)), scaled((2, 1, 0))),
    ), cam0,
  ).filter(p => p.kind == "seg")
  assert(tiny-or-large.len() == 3,
    message: "face clipping changed under scale " + repr(scale))
  assert(calc.abs(tiny-or-large.first().b.at(0) / scale + 1) < 1e-9)
  assert(calc.abs(tiny-or-large.at(1).a.at(0) / scale) < 1e-9)
}

// A translucent face never erases data. It may split the line at visibility
// boundaries to improve painter keys, but the fragments cover the full line.
#let translucent-crossing = _clip-lines(
  ((..screen-face, fill-opacity: 55%), seg((-2, -1, 0), (2, 1, 0))), cam0,
).filter(p => p.kind == "seg")
#assert(translucent-crossing.first().a == (-2, -1, 0))
#assert(translucent-crossing.last().b == (2, 1, 0))
#for i in range(1, translucent-crossing.len()) {
  assert(translucent-crossing.at(i - 1).b == translucent-crossing.at(i).a,
    message: "translucent face split must preserve the complete line")
}

// --- meshes explode into independently-sorted per-face primitives ------------
// A 6-sided capped cylinder has 6 + 2 = 8 faces; each becomes its own face prim.
#let msc = build-scene(cylinder((0, 0, 0), (0, 0, 2), 1, segments: 6))
#let mordered = sort-prims(msc.prims, cam0)
#assert(mordered.len() == 8, message: "mesh should explode to 8 faces, got " + str(mordered.len()))
#assert(mordered.all(p => p.kind == "face"), message: "exploded mesh faces must all be `face`")

// Adaptive mesh visibility: opaque closed meshes cull rear faces, translucent
// meshes keep both sides (rear faces are tagged for quieter hidden strokes), and
// an explicit `cull: none` restores all-face rendering.
#let cube-v = (
  (-1,-1,-1), (1,-1,-1), (1,1,-1), (-1,1,-1),
  (-1,-1, 1), (1,-1, 1), (1,1, 1), (-1,1, 1),
)
#let cube-f = (
  (0,3,2,1), (4,5,6,7), (0,1,5,4),
  (1,2,6,5), (2,3,7,6), (3,0,4,7),
)
#let opaque-cube = _prepare-faces(
  (mesh(cube-v, cube-f, fill-opacity: 0%),), cam0,
)
#assert(opaque-cube.len() == 5,
  message: "axis-on opaque cube should drop its rear face and retain silhouette faces")
#let translucent-cube = _prepare-faces(
  (mesh(cube-v, cube-f, fill-opacity: 55%),), cam0,
)
#assert(translucent-cube.len() == 6)
#assert(translucent-cube.filter(p => p.at("rear-face", default: false)).len() == 1)
#let rear-record = _record(
  cam0, 1, default-theme,
  translucent-cube.find(p => p.at("rear-face", default: false)),
)
#assert(rear-record.stroke.paint != default-theme.face.color.darken(default-theme.face.stroke-darken),
  message: "translucent rear edge should be visually quieter than the visible outline")
#let no-rear-stroke = _prepare-faces(
  (mesh(cube-v, cube-f, fill-opacity: 55%, hidden-stroke: none),), cam0,
).find(p => p.at("rear-face", default: false))
#assert(_record(cam0, 1, default-theme, no-rear-stroke).stroke == none)
#let uncull-cube = _prepare-faces(
  (mesh(cube-v, cube-f, fill-opacity: 0%, cull: none),), cam0,
)
#assert(uncull-cube.len() == 6)
#let front-culled-cube = _prepare-faces(
  (mesh(cube-v, cube-f, fill-opacity: 0%, cull: "front"),), cam0,
)
#assert(front-culled-cube.len() == 5)
#assert(front-culled-cube.filter(p => p.at("rear-face", default: false)).len() == 1)
#for scale in (1e-6, 1e6) {
  let scaled(p) = p.map(x => x * scale)
  let scaled-cube = _prepare-faces(
    (mesh(cube-v.map(scaled), cube-f, fill-opacity: 0%),), cam0,
  )
  assert(scaled-cube.len() == 5,
    message: "adaptive culling changed under scale " + repr(scale))
}

// --- sphere-fill colour-mix guard (the CeTZ 0.5.2 weighting gotcha) -----------
// The sphere body tint must be color.mix((white, 25%), (col, 75%)), NOT the
// mis-weighted white.mix((col, 55%)) (which renormalises to a paler tone).
#let col = rgb("#c44e52")
#assert(
  _sphere-fill(col) == color.mix((white, 25%), (col, 75%)),
  message: "sphere fill uses the wrong color.mix weighting",
)
#assert(
  _sphere-fill(col) != white.mix((col, 75%)),
  message: "sphere fill regressed to the white.mix(..) mis-weighting",
)

// --- sphere gradient: specular stop (issue #30) --------------------------------
// specular: false must reproduce the classic pre-specular gradient EXACTLY —
// the graceful-degradation opt-out the M4 design doc requires.
// NOTE: whole-gradient `==` is unreliable in Typst 0.14.2 (identically
// constructed gradients compare unequal), so the pin compares componentwise:
// stops, center, and radius — together these are the full radial constructor.
#let classic = gradient.radial(
  (color.mix((white, 70%), (col, 30%)), 0%),
  (_sphere-fill(col), 25%),
  (col, 55%),
  (col.darken(30%), 100%),
  center: (35%, 30%),
  radius: 110%,
)
#let no-spec = _sphere-gradient(col, specular: false)
#assert.eq(no-spec.stops(), classic.stops(),
  message: "specular: false must have the exact classic gradient stops")
#assert.eq(no-spec.center(), classic.center(),
  message: "specular: false must keep the classic gradient center")
#assert.eq(no-spec.radius(), classic.radius(),
  message: "specular: false must keep the classic gradient radius")
// The default gradient gains the specular core: five stops, a first stop
// strictly lighter than the classic highlight, and the issue-#8 mid-tone
// _sphere-fill(col) still present as a stop.
#let spec-stops = _sphere-gradient(col).stops()
#assert.eq(spec-stops.len(), 5, message: "specular gradient has five stops")
#assert.eq(spec-stops.first().at(0), color.mix((white, 92%), (col, 8%)))
#assert(spec-stops.map(s => s.at(0)).contains(_sphere-fill(col)),
  message: "the issue-#8 mid-tone must survive as a stop of the new gradient")
#assert(spec-stops != no-spec.stops(),
  message: "default gradient must actually differ (the repaint is intended)")

// --- perspective: projected sphere radius scales with depth -------------------
#let pcam = camera(azimuth: 0deg, elevation: 0deg, mode: "perspective", distance: 10)
#let near-sp = _projected-sphere((kind: "sphere", center: (0, 5, 0), r: 1.0), pcam)
#assert(calc.abs(near-sp.r - 2.0) < 1e-9, message: "near sphere silhouette doubles")
#let far-sp = _projected-sphere((kind: "sphere", center: (0, -10, 0), r: 1.0), pcam)
#assert(calc.abs(far-sp.r - 0.5) < 1e-9, message: "far sphere silhouette halves")
#assert(near-sp.r > far-sp.r, message: "nearer sphere must project larger")
// negative control: the orthographic occluder radius is untouched
#assert.eq(_projected-sphere((kind: "sphere", center: (0, 5, 0), r: 1.0), cam0).r, 1.0)

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

// Standalone rendering disables anchor-node emission internally. Composed
// callers may make the same performance choice explicitly when no later CeTZ
// command references the logical names; the default registering path is covered
// in test-anchors.typ.
#cetz.canvas(length: 1cm, {
  scene-group(
    build-scene(sphere((0, 0, 0), 0.4, name: "unexported")),
    cam0,
    register-anchors: false,
  )
})
