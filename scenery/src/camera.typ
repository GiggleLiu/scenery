// Camera + orthographic projection for the scene core.
// Pure functions, no cetz dependency: a camera is a plain dictionary and
// `project` maps a 3-point to screen coordinates plus a depth value.

/// Creates an orthographic camera.
///
/// The projection is pinned (see `project`): with `azimuth == elevation == 0deg`
/// the view looks along $+y$ with $+x$ to the right and $+z$ up; depth grows
/// toward the viewer.
///
/// - azimuth (angle): Rotation about the vertical axis.
/// - elevation (angle): Tilt above the horizontal plane.
/// -> camera
#let camera(azimuth: 25deg, elevation: 15deg) = (
  mode: "orthographic",
  azimuth: azimuth,
  elevation: elevation,
)

/// Creates a 2D identity camera.
///
/// Flat diagrams share the 3D pipeline: `project` passes $(x, y, z)$ straight
/// through to `(sx: x, sy: y, depth: 0)`.
/// -> camera
#let camera-2d() = (mode: "2d")

/// Projects a 3-point to screen coordinates plus depth.
///
/// For an orthographic camera the pinned convention is
/// $x_1 = x cos("az") + y sin("az")$, $y_1 = -x sin("az") + y cos("az")$,
/// $"sx" = x_1$, $"sy" = -y_1 sin("el") + z cos("el")$,
/// $"depth" = y_1 cos("el") + z sin("el")$.
///
/// For a 2D camera the point passes through as `(sx: x, sy: y, depth: 0)`.
///
/// - cam (camera): The camera to project through.
/// - point (vector): The 3-point $(x, y, z)$ to project.
/// -> dictionary
#let project(cam, point) = {
  let (x, y, z) = point
  if cam.mode == "2d" {
    return (sx: x, sy: y, depth: 0)
  }
  let az = cam.azimuth
  let el = cam.elevation
  let x1 = x * calc.cos(az) + y * calc.sin(az)
  let y1 = -x * calc.sin(az) + y * calc.cos(az)
  (
    sx: x1,
    sy: -y1 * calc.sin(el) + z * calc.cos(el),
    depth: y1 * calc.cos(el) + z * calc.sin(el),
  )
}
