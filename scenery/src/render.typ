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
#import "anchors.typ": resolve-scene

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

// The interval in [0, 1] where a quadratic `a t^2 + b t + c` is <= 0.
// The quadratics used below are squared distances minus a radius squared, so
// `a` is non-negative and their sublevel set is either empty or one interval.
#let _quadratic-interval(a, b, c) = {
  if a == 0 {
    if c <= 0 { (0.0, 1.0) } else { none }
  } else {
    let disc = b * b - 4 * a * c
    if disc <= 0 { none } else {
      let root = calc.sqrt(disc)
      let lo = calc.max(0.0, (-b - root) / (2 * a))
      let hi = calc.min(1.0, (-b + root) / (2 * a))
      if hi > lo { (lo, hi) } else { none }
    }
  }
}

// Restrict an interval to the half-line where h(t) = h0 + dh*t is in front
// of (`front: true`) or behind (`front: false`) the sphere centre plane.
#let _depth-half(interval, h0, dh, front: false) = {
  if interval == none { return none }
  let (lo, hi) = interval
  if dh == 0 {
    let keep = if front { h0 >= 0 } else { h0 <= 0 }
    if keep { interval } else { none }
  } else {
    let cross = -h0 / dh
    if front {
      if dh > 0 { lo = calc.max(lo, cross) }
      else { hi = calc.min(hi, cross) }
    } else {
      if dh > 0 { hi = calc.min(hi, cross) }
      else { lo = calc.max(lo, cross) }
    }
    if hi > lo { (lo, hi) } else { none }
  }
}

// Parameter intervals of line a--b hidden by an opaque sphere under an
// orthographic camera. Behind the centre plane, the whole projected disk hides
// the line. In front of that plane, only the part inside the actual sphere is
// hidden; a line nearer than the sphere's front surface remains visible.
#let _line-sphere-occlusion(a, b, sp, camera) = {
  let pa = project(camera, a)
  let pb = project(camera, b)
  let pc = project(camera, sp.center)
  let (qx, qy) = (pa.sx - pc.sx, pa.sy - pc.sy)
  let (dx, dy) = (pb.sx - pa.sx, pb.sy - pa.sy)
  let h0 = pa.depth - pc.depth
  let dh = pb.depth - pa.depth
  let aa = dx * dx + dy * dy
  let bb = 2 * (qx * dx + qy * dy)
  let cc = qx * qx + qy * qy - sp.r * sp.r
  let disk = _quadratic-interval(aa, bb, cc)
  let ball = _quadratic-interval(
    aa + dh * dh,
    bb + 2 * h0 * dh,
    cc + h0 * h0,
  )
  let hidden = ()
  let rear = _depth-half(disk, h0, dh)
  let front = _depth-half(ball, h0, dh, front: true)
  if rear != none { hidden.push(rear) }
  if front != none { hidden.push(front) }
  (hidden: hidden, disk: disk)
}

#let _merge-intervals(intervals) = {
  // These are dimensionless line parameters, so this tolerance is independent
  // of the scene's world-unit scale.
  let eps = 1e-12
  let merged = ()
  for cur in intervals.sorted(key: x => x.at(0)) {
    if merged.len() == 0 {
      merged.push(cur)
    } else {
      let prev = merged.last()
      if cur.at(0) <= prev.at(1) + eps {
        merged = merged.slice(0, merged.len() - 1)
        merged.push((prev.at(0), calc.max(prev.at(1), cur.at(1))))
      } else {
        merged.push(cur)
      }
    }
  }
  merged
}

#let _lerp-point(a, b, t) = vadd(vscale(a, 1 - t), vscale(b, t))

/// Splits line primitives into the portions visible around opaque spheres.
///
/// This is deliberately separate from `sort-prims`: the public helper remains
/// a sorting-only operation, while the render path can assign a correct depth
/// key to every visible line fragment. Segment and edge styles are preserved.
#let _clip-lines(prims, camera) = {
  let eps = 1e-12 // dimensionless parameter-space tolerance
  let spheres = prims.filter(p => p.kind == "sphere")
  let out = ()
  for p in prims {
    if p.kind == "seg" or p.kind == "edge" {
      let hidden = ()
      let cuts = (0.0, 1.0)
      for sp in spheres {
        let occ = _line-sphere-occlusion(p.a, p.b, sp, camera)
        hidden += occ.hidden
        // Split even a fully visible line where it enters/leaves the projected
        // disk. That gives the overlapping foreground piece its own depth key
        // instead of letting a distant, non-overlapping tail drag its midpoint
        // behind the sphere.
        if occ.disk != none { cuts += (occ.disk.at(0), occ.disk.at(1)) }
      }
      let merged = _merge-intervals(hidden)
      for iv in merged {
        cuts += (iv.at(0), iv.at(1))
      }
      cuts = cuts.sorted()
      let unique = ()
      for t in cuts {
        if unique.len() == 0 or t - unique.last() > eps { unique.push(t) }
      }
      let visible = ()
      for i in range(unique.len() - 1) {
        let iv = (unique.at(i), unique.at(i + 1))
        let mid = (iv.at(0) + iv.at(1)) / 2
        let is-hidden = merged.any(h => mid > h.at(0) and mid < h.at(1))
        if iv.at(1) - iv.at(0) > eps and not is-hidden { visible.push(iv) }
      }
      for iv in visible {
        let q = p
        q.insert("a", _lerp-point(p.a, p.b, iv.at(0)))
        q.insert("b", _lerp-point(p.a, p.b, iv.at(1)))
        out.push(q)
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
      // an explicit `stroke` hook (e.g. `none` from the solid generators)
      // overrides the theme-derived facet stroke
      stroke: st.at(
        "stroke",
        default: (paint: st.color.darken(st.stroke-darken), thickness: st.stroke-width),
      ),
    )
  } else if k == "label" {
    (
      kind: k,
      pos: _screen(camera, unit, p.at),
      body: text(size: st.size, fill: st.color, weight: st.weight, p.text),
      anchor: st.at("text-anchor", default: none),
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
/// The screen-space bounding box `(x0, y0, x1, y1)` of a scene's AABB: the span
/// of the eight AABB corners' projected `(sx, sy)`. Placement of annotations
/// (triad bottom-left, legend/colorbar on the right) is derived from this.
#let _projected-screen-bbox(camera, bbox) = {
  let (mn, mx) = (bbox.min, bbox.max)
  let xs = ()
  let ys = ()
  for x in (mn.at(0), mx.at(0)) {
    for y in (mn.at(1), mx.at(1)) {
      for z in (mn.at(2), mx.at(2)) {
        let q = project(camera, (x, y, z))
        xs.push(q.sx)
        ys.push(q.sy)
      }
    }
  }
  (calc.min(..xs), calc.min(..ys), calc.max(..xs), calc.max(..ys))
}

/// - scene (dictionary): A scene `(prims, bbox)` from `build-scene`.
/// - camera (camera): The camera to project through.
/// - theme (dictionary): A theme (see `default-theme`).
/// - unit (float): Canvas units per scene unit.
/// - axes (none, dictionary): `(vectors:, names?:)` — an axes triad placed
///   bottom-left of the projected bbox (see `annotate.axes-triad`).
/// - legend (none, array): `(label, color)` entries placed to the right (see
///   `annotate.legend`).
/// - colorbar (none, dictionary): `(colormap:, range:)` placed on the right,
///   spanning the scene height (see `annotate.colorbar`).
/// -> content
#let scene-group(
  scene,
  camera,
  theme: default-theme,
  unit: 1,
  axes: none,
  legend: none,
  colorbar: none,
) = {
  let scene = resolve-scene(scene, camera)
  // All geometry resolved to plain data before the wildcard import, so the loop
  // below cannot be tripped by cetz re-exporting `project`/`scale`.
  let records = sort-prims(_clip-lines(scene.prims, camera), camera)
    .map(p => _record(camera, unit, theme, p))
  // Annotation placement, in canvas coords (screen projection times `unit`).
  let sb = _projected-screen-bbox(camera, scene.bbox)
  let (x0, y0, x1, y1) = (sb.at(0) * unit, sb.at(1) * unit, sb.at(2) * unit, sb.at(3) * unit)
  import cetz.draw: *
  // Register one anchor-only CeTZ group per logical scenery object. Geometry is
  // still emitted anonymously below because depth clipping can split one object
  // into multiple draw records.
  for (object-name, object-anchors) in scene.anchors {
    group(name: object-name, {
      for (anchor-name, point) in object-anchors {
        anchor(anchor-name, _screen(camera, unit, point))
      }
    })
  }
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
      content(r.pos, r.body, anchor: r.anchor)
    }
  }
  // Annotation furniture, drawn on top of the scene. Deferred import breaks the
  // render <-> annotate reference cycle (annotate reuses `_sphere-gradient`).
  if axes != none or legend != none or colorbar != none {
    import "annotate.typ": axes-triad as _triad-cmd, legend as _legend-cmd, colorbar as _colorbar-cmd
    if axes != none {
      _triad-cmd(
        camera,
        axes.vectors,
        names: axes.at("names", default: ("x", "y", "z")),
        origin: (x0 - 0.5, y0 - 0.5),
      )
    }
    if legend != none {
      _legend-cmd(legend, origin: (x1 + 0.7, y1))
    }
    if colorbar != none {
      let cx = x1 + (if legend != none { 2.4 } else { 0.7 })
      _colorbar-cmd(colorbar.colormap, colorbar.range, origin: (cx, y0), height: y1 - y0)
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
/// - axes (none, dictionary): `(vectors:, names?:)` axes-triad spec, placed
///   bottom-left (see `scene-group`).
/// - legend (none, array): `(label, color)` legend entries, placed right.
/// - colorbar (none, dictionary): `(colormap:, range:)` colorbar spec, placed
///   right.
/// -> content
#let render-scene(
  scene,
  camera,
  width: 8cm,
  theme: default-theme,
  axes: none,
  legend: none,
  colorbar: none,
) = {
  let scene = resolve-scene(scene, camera)
  let w = _projected-width(camera, scene.bbox)
  let unit = if w > 0 { (width / 1cm) / w } else { 1.0 }
  cetz.canvas(length: 1cm, scene-group(
    scene,
    camera,
    theme: theme,
    unit: unit,
    axes: axes,
    legend: legend,
    colorbar: colorbar,
  ))
}
