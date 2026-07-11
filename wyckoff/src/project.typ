/// Orthographic projector. Convention (pinned by tests/test-scene.typ):
/// az=el=0 looks along +y with +x right, +z up; depth grows toward the viewer.
#let projector(view) = {
  let az = view.at("azimuth", default: 25deg)
  let el = view.at("elevation", default: 15deg)
  p => {
    let (x, y, z) = p
    let x1 = x * calc.cos(az) + y * calc.sin(az)
    let y1 = -x * calc.sin(az) + y * calc.cos(az)
    (
      sx: x1,
      sy: -y1 * calc.sin(el) + z * calc.cos(el),
      depth: y1 * calc.cos(el) + z * calc.sin(el),
    )
  }
}
