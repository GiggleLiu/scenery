#import "/src/camera.typ": camera, camera-2d, project, project-scale

// Pin the orthographic projection convention:
// az=el=0 looks along +y with +x right, +z up; depth grows toward the viewer.
#let cam0 = camera(azimuth: 0deg, elevation: 0deg)
#let s = project(cam0, (1.0, 0.0, 0.0))
#assert(calc.abs(s.sx - 1.0) < 1e-9 and calc.abs(s.sy) < 1e-9)
#let s = project(cam0, (0.0, 0.0, 1.0))
#assert(calc.abs(s.sy - 1.0) < 1e-9 and calc.abs(s.depth) < 1e-9)
#let s = project(cam0, (0.0, 1.0, 0.0))
#assert(calc.abs(s.depth - 1.0) < 1e-9, message: "+y toward viewer at az=el=0")
#let top = project(camera(azimuth: 0deg, elevation: 90deg), (0.0, 0.0, 1.0))
#assert(calc.abs(top.depth - 1.0) < 1e-9, message: "top view: +z toward viewer")

// 2D identity mode: (x, y, z) -> (sx: x, sy: y, depth: 0) exactly.
#let flat = project(camera-2d(), (3, 4, 9))
#assert(flat == (sx: 3, sy: 4, depth: 0), message: "2D mode is pass-through with depth 0")

// Negative control: the azimuth-sign-flipped fixture must differ from the
// pinned convention, so the sign of the rotation is genuinely tested.
#let cam = camera(azimuth: 25deg, elevation: 15deg)
#let pinned = project(cam, (1.0, 2.0, 3.0))
#let (x, y, z) = (1.0, 2.0, 3.0)
#let az = 25deg
#let el = 15deg
#let x1-flipped = x * calc.cos(az) - y * calc.sin(az) // sign flip
#let y1 = -x * calc.sin(az) + y * calc.cos(az)
#let flipped = (
  sx: x1-flipped,
  sy: -y1 * calc.sin(el) + z * calc.cos(el),
  depth: y1 * calc.cos(el) + z * calc.sin(el),
)
#assert(calc.abs(pinned.sx - flipped.sx) > 1e-6, message: "flipped azimuth sign must differ from pinned convention")

// --- perspective camera (issue #29) ------------------------------------------

// The orthographic camera dict is BYTE-IDENTICAL to the pre-perspective shape:
// exactly three keys, no distance field. (The gallery gate depends on this.)
#assert.eq(
  camera(azimuth: 25deg, elevation: 15deg),
  (mode: "orthographic", azimuth: 25deg, elevation: 15deg),
)

// project-scale is the literal 1.0 for orthographic and 2d cameras.
#assert.eq(project-scale(cam0, 123.4), 1.0)
#assert.eq(project-scale(camera(azimuth: 25deg, elevation: 15deg), -7.0), 1.0)
#assert.eq(project-scale(camera-2d(), 0), 1.0)

// Pinned perspective math at az=el=0 (view-space == world: depth = y).
// s(depth) = distance / (distance - depth); a point at depth 5 with
// distance 10 doubles its screen offsets.
#let pcam = camera(azimuth: 0deg, elevation: 0deg, mode: "perspective", distance: 10)
#assert.eq(pcam.mode, "perspective")
#assert.eq(pcam.distance, 10)
#let near = project(pcam, (1.0, 5.0, 0.0))
#assert(calc.abs(near.sx - 2.0) < 1e-9, message: "near point must be magnified 2x")
#assert(calc.abs(near.depth - 5.0) < 1e-9,
  message: "depth key stays the unscaled view depth (sorting is unchanged)")
#assert(calc.abs(project-scale(pcam, 5.0) - 2.0) < 1e-9)
#let far = project(pcam, (1.0, -10.0, 0.0))
#assert(calc.abs(far.sx - 0.5) < 1e-9, message: "far point must shrink to 0.5x")
#assert(near.sx > far.sx, message: "nearer of two equal world offsets projects larger")
// distance -> orthographic limit
#let almost-ortho = project(camera(azimuth: 0deg, elevation: 0deg,
  mode: "perspective", distance: 1e9), (1.0, 5.0, 0.0))
#assert(calc.abs(almost-ortho.sx - 1.0) < 1e-6)

// REGRESSION PIN: orthographic projected values are unchanged by the new
// branch — the exact hand formula from the module docs.
#let q = project(camera(azimuth: 25deg, elevation: 15deg), (1.0, 2.0, 3.0))
#let x1 = 1.0 * calc.cos(25deg) + 2.0 * calc.sin(25deg)
#let y1 = -1.0 * calc.sin(25deg) + 2.0 * calc.cos(25deg)
#assert.eq(q, (
  sx: x1,
  sy: -y1 * calc.sin(15deg) + 3.0 * calc.cos(15deg),
  depth: y1 * calc.cos(15deg) + 3.0 * calc.sin(15deg),
))

Camera OK
