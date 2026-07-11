// Painter's-algorithm renderer: depth-sort scene primitives, then paint them
// back-to-front with cetz. Generalised from the validated `wyckoff/src/render.typ`
// (gradient-shaded sphere balls, translucent faces) with two changes: styling
// comes from a theme dict instead of hardcoded atom colours, and mesh/`face`
// polygons are flat-shaded from a single world light direction.
//
// Two cetz 0.5.2 gotchas the wyckoff reference documents are honoured here:
//   * `import cetz.draw: *` re-exports names like `scale`/`project` that would
//     shadow parameters and our camera projection. All geometry is therefore
//     computed in pure helpers BEFORE the wildcard import, and the drawing loop
//     touches only cetz's `line`/`circle`/`content`.
//   * colour mixing must weight explicitly, `color.mix((white, 25%), (col, 75%))`,
//     not `white.mix((col, 75%))` (which renormalises to a much paler tone).
//     `_sphere-fill` is the guarded, pure helper carrying that weighting.

#import "@preview/cetz:0.5.2"
#import "camera.typ": project
#import "linalg.typ": vadd, vscale
#import "style.typ": default-theme, resolve-style, face-brightness

// --- sphere shading ---------------------------------------------------------

/// The body tint of a shaded sphere of base colour `col`: the documented
/// mid-tone `color.mix((white, 25%), (col, 75%))` (wyckoff parity — issue #8
/// pixel-compares against it). This is the pure, testable
/// guard against the `white.mix(..)` mis-weighting (see the module header); it
/// is the mid stop of `_sphere-gradient`.
///
/// - col (color): The sphere's base colour.
/// -> color
#let _sphere-fill(col) = color.mix((white, 25%), (col, 75%))

/// Radial "3D ball" gradient for a sphere of base colour `col`: a bright
/// highlight up-left of centre fading through the `_sphere-fill` body and the
/// base colour to a darkened rim.
///
/// - col (color): The sphere's base colour.
/// -> gradient
#let _sphere-gradient(col) = gradient.radial(
  (color.mix((white, 70%), (col, 30%)), 0%),
  (_sphere-fill(col), 25%),
  (col, 55%),
  (col.darken(30%), 100%),
  center: (35%, 30%),
  radius: 110%,
)

// --- depth sorting (pure) ---------------------------------------------------

/// Midpoint of two points.
#let _mid(a, b) = vscale(vadd(a, b), 0.5)

/// Centroid of a point array.
#let _centroid(pts) = vscale(pts.fold((0.0, 0.0, 0.0), vadd), 1 / pts.len())

/// The 3D point whose camera depth is a primitive's depth key.
#let _depth-point(p) = {
  let k = p.kind
  if k == "sphere" { p.center }
  else if k == "seg" or k == "edge" { _mid(p.a, p.b) }
  else if k == "arrow" { _mid(p.from, p.to) }
  else if k == "face" { _centroid(p.pts) }
  else { p.center } // unreachable: labels/meshes handled before this
}

/// Explodes any `mesh` primitive into one `face` primitive per mesh face,
/// carrying the mesh's styling hooks. Non-mesh primitives pass through. This
/// lets a mesh's near and far faces sort independently in `sort-prims`.
#let _explode(prims) = {
  let out = ()
  for p in prims {
    if p.kind == "mesh" {
      let hooks = (:)
      for (kk, vv) in p {
        if kk not in ("kind", "vertices", "faces") { hooks.insert(kk, vv) }
      }
      for f in p.faces {
        out.push((kind: "face", pts: f.map(i => p.vertices.at(i)), ..hooks))
      }
    } else {
      out.push(p)
    }
  }
  out
}

/// Depth-sorts scene primitives back-to-front for painter's-algorithm drawing.
///
/// Pure — no cetz. Each primitive gets a scalar depth key from `camera`:
/// spheres use their centre, seg/edge/arrow their midpoint, faces their
/// centroid, and labels a huge constant so they always paint last (on top).
/// Meshes are first exploded into per-face `face` primitives, each keyed by its
/// own centroid, so a single mesh's faces sort independently. Depth grows toward
/// the viewer, so ascending order is far-to-near.
///
/// - prims (array): Scene primitives (as from `build-scene(..).prims`).
/// - camera (camera): The camera to key depths through.
/// -> array
#let sort-prims(prims, camera) = {
  let keyed = _explode(prims).map(p => {
    let depth = if p.kind == "label" { 1e9 } else {
      project(camera, _depth-point(p)).depth
    }
    (..p, depth: depth)
  })
  keyed.sorted(key: p => p.depth)
}

// --- pure draw-record preparation -------------------------------------------

/// Projects a 3D point to canvas coordinates: screen position times `unit`.
#let _screen(camera, unit, p) = {
  let q = project(camera, p)
  (q.sx * unit, q.sy * unit)
}

/// Turns one depth-sorted primitive into a plain-data draw record (screen
/// coordinates, resolved colours and thicknesses). No cetz here, so the drawing
/// loop can run entirely on cetz names without shadowing our projection.
#let _record(camera, unit, theme, p) = {
  let st = resolve-style(theme, p)
  let k = p.kind
  if k == "sphere" {
    (
      kind: k,
      pos: _screen(camera, unit, p.center),
      radius: p.r * unit,
      color: st.color,
      stroke: (paint: st.color.darken(st.stroke-darken), thickness: st.stroke-width),
    )
  } else if k == "seg" {
    (
      kind: k,
      a: _screen(camera, unit, p.a),
      b: _screen(camera, unit, p.b),
      stroke: (paint: st.color, thickness: st.w * unit * 1cm, cap: "round"),
    )
  } else if k == "edge" {
    (
      kind: k,
      a: _screen(camera, unit, p.a),
      b: _screen(camera, unit, p.b),
      stroke: (paint: st.color, thickness: st.width),
    )
  } else if k == "arrow" {
    (
      kind: k,
      a: _screen(camera, unit, p.from),
      b: _screen(camera, unit, p.to),
      stroke: (paint: st.color, thickness: st.w * unit * 1cm, cap: "round"),
      mark: (end: st.head, fill: st.color, scale: st.head-scale * st.w * unit),
    )
  } else if k == "face" {
    let b = if st.at("shade", default: true) { face-brightness(p.pts, theme.light) } else { 1.0 }
    let fill = st.color.darken((1.0 - b) * 100%)
    let op = st.at("fill-opacity", default: 0%)
    if op != 0% { fill = fill.transparentize(op) }
    (
      kind: k,
      pts: p.pts.map(q => _screen(camera, unit, q)),
      fill: fill,
      stroke: (paint: st.color.darken(st.stroke-darken), thickness: st.stroke-width),
    )
  } else if k == "label" {
    (
      kind: k,
      pos: _screen(camera, unit, p.at),
      body: text(size: st.size, fill: st.color, weight: st.weight, p.text),
    )
  } else {
    panic("unknown primitive kind: " + k)
  }
}

// --- cetz emission ----------------------------------------------------------

/// Raw cetz draw commands for `scene`, depth-sorted and painted back-to-front,
/// for composition inside an existing `cetz.canvas`.
///
/// Coordinates are the camera's screen projection times `unit` (canvas units per
/// scene unit). Spheres are gradient-shaded balls (radius in scene units, no
/// perspective foreshortening); segments are round-capped strokes; edges thin
/// neutral lines; arrows strokes with a scaled head; faces flat-shaded, possibly
/// translucent, filled polygons; labels content drawn last.
///
/// - scene (dictionary): A scene `(prims, bbox)` from `build-scene`.
/// - camera (camera): The camera to project through.
/// - theme (dictionary): A theme (see `default-theme`).
/// - unit (float): Canvas units per scene unit.
/// -> content
#let scene-group(scene, camera, theme: default-theme, unit: 1) = {
  // All geometry resolved to plain data before the wildcard import, so the loop
  // below cannot be tripped by cetz re-exporting `project`/`scale`.
  let records = sort-prims(scene.prims, camera).map(p => _record(camera, unit, theme, p))
  import cetz.draw: *
  for r in records {
    if r.kind == "sphere" {
      circle(r.pos, radius: r.radius, fill: _sphere-gradient(r.color), stroke: r.stroke)
    } else if r.kind == "seg" or r.kind == "edge" {
      line(r.a, r.b, stroke: r.stroke)
    } else if r.kind == "arrow" {
      line(r.a, r.b, stroke: r.stroke, mark: r.mark)
    } else if r.kind == "face" {
      line(..r.pts, close: true, fill: r.fill, stroke: r.stroke)
    } else if r.kind == "label" {
      content(r.pos, r.body)
    }
  }
}

// --- top-level canvas -------------------------------------------------------

/// The projected screen-space width of a scene's bounding box: the span of the
/// eight AABB corners' `sx` after projection.
#let _projected-width(camera, bbox) = {
  let (mn, mx) = (bbox.min, bbox.max)
  let xs = ()
  for x in (mn.at(0), mx.at(0)) {
    for y in (mn.at(1), mx.at(1)) {
      for z in (mn.at(2), mx.at(2)) {
        xs.push(project(camera, (x, y, z)).sx)
      }
    }
  }
  calc.max(..xs) - calc.min(..xs)
}

/// Renders a scene to Typst content: a `cetz.canvas` (length 1cm) scaled so the
/// scene's projected bounding-box width equals `width`.
///
/// - scene (dictionary): A scene `(prims, bbox)` from `build-scene`.
/// - camera (camera): The camera to project through.
/// - width (length): Target on-page width of the scene's bounding box.
/// - theme (dictionary): A theme (see `default-theme`).
/// -> content
#let render-scene(scene, camera, width: 8cm, theme: default-theme) = {
  let w = _projected-width(camera, scene.bbox)
  let unit = if w > 0 { (width / 1cm) / w } else { 1.0 }
  cetz.canvas(length: 1cm, scene-group(scene, camera, theme: theme, unit: unit))
}
