#import "/src/camera.typ": camera, camera-2d, project

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

Camera OK
