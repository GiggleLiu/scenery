// Crystal-figure builder on top of the scenery core (issue #8).
//
// Replaces wyckoff's former private engine (`linalg.typ`, `project.typ`,
// `scene.typ`, `render.typ`): geometry is turned into scenery *primitives*
// (`sphere`/`seg`/`face`/`edge`/`label`) carrying wyckoff's per-atom colours and
// strokes as style hooks, and drawn through scenery's `scene-group`. Two wyckoff
// specifics are reproduced here rather than in the core:
//   * the coverage-suppression heuristic (`occlude`), re-implemented as a pure
//     screen-space pre-filter with the SAME slacks (`2*r`, `0.45*w`) the old
//     `render.typ` used (controller ruling, issue #8);
//   * legend/axes furniture, drawn via scenery's `legend`/`axes-triad` with
//     origins derived from wyckoff's screen-space bbox for pixel parity.

#import "@preview/scenery:0.1.0" as scenery
#import "@preview/cetz:0.5.2"
#import "data.typ": element-info
#import "geometry.typ": display-atoms, cell-edges, find-bonds, find-polyhedra

/// Build a pure-data scene of scenery primitives (3D, unprojected) plus the
/// screen-space bbox and element list wyckoff's renderer needs. Primitives are
/// UNFILTERED here (coverage suppression happens at render time via `occlude`),
/// matching the old `scene.typ` contract that `tests/test-scene.typ` pins.
#let build-scene(
  structure,
  view: (azimuth: 25deg, elevation: 15deg),
  supercell: (1, 1, 1),
  bonds: auto,          // auto | none | rules array
  polyhedra: (),        // element list
  radius: 0.45,
  bond-width: 0.16,
  labels: false,
  colors: (:),
) = {
  let az = view.at("azimuth", default: 25deg)
  let elev = view.at("elevation", default: 15deg)
  let cam = scenery.camera(azimuth: az, elevation: elev)

  // Depth-only offset: the old renderer pushed polyhedra faces back by 0.01 in
  // depth (`cdepth - 0.01`). The camera-forward direction changes ONLY depth
  // (screen x/y are invariant), so offsetting face vertices along it by -0.01
  // reproduces the old depth key exactly while leaving projected geometry — and
  // hence the screen bbox and every drawn pixel — untouched.
  let gdepth = (-calc.sin(az) * calc.cos(elev), calc.cos(az) * calc.cos(elev), calc.sin(elev))
  let face-offset = scenery.vscale(gdepth, -0.01)

  let shown = display-atoms(structure, supercell: supercell)
  let prims = ()
  let rdisp(el) = radius * element-info(el).r-atom
  let color-of(el) = colors.at(el, default: element-info(el).color)

  // Spheres, then labels, then bond segs, then polyhedra faces, then cell edges:
  // this push order is the stable-sort tie-break the old renderer relied on.
  for a in shown {
    prims.push(scenery.sphere(a.cart, rdisp(a.element),
      color: color-of(a.element), element: a.element))
  }
  if labels {
    for a in shown {
      prims.push(scenery.label(a.cart, a.element))
    }
  }

  let blist = if bonds == none { () } else { find-bonds(shown, bonds) }
  for b in blist {
    let (pa, pb) = (shown.at(b.i), shown.at(b.j))
    let dir = scenery.vnorm(scenery.vsub(pb.cart, pa.cart))
    let a0 = scenery.vadd(pa.cart, scenery.vscale(dir, 0.9 * rdisp(pa.element)))
    let b0 = scenery.vsub(pb.cart, scenery.vscale(dir, 0.9 * rdisp(pb.element)))
    let mid = scenery.lerp(a0, b0, 0.5)
    // Two-tone bond: one seg per half, coloured by its own atom.
    for (p, q, el) in ((a0, mid, pa.element), (mid, b0, pb.element)) {
      prims.push(scenery.seg(p, q,
        color: color-of(el).darken(10%), w: bond-width))
    }
  }

  if polyhedra.len() > 0 {
    for poly in find-polyhedra(shown, blist, polyhedra) {
      let col = color-of(shown.at(poly.center).element)
      for f in poly.faces {
        // shade: false — the old renderer never lit faces (flat translucent fill).
        prims.push(scenery.face(f.map(p => scenery.vadd(p, face-offset)),
          color: col, shade: false))
      }
    }
  }

  for (ea, eb) in cell-edges(structure, supercell: supercell) {
    for t in range(8) {
      let p = scenery.lerp(ea, eb, t / 8)
      let q = scenery.lerp(ea, eb, (t + 1) / 8)
      prims.push(scenery.edge(p, q, color: luma(120), width: 0.7pt))
    }
  }

  // Screen-space bbox (wyckoff parity): projected extents, including each
  // sphere's radius added in screen space (NOT scenery's 3D-AABB projection).
  let xs = ()
  let ys = ()
  for p in prims {
    if p.kind == "sphere" {
      let s = scenery.project(cam, p.center)
      xs += (s.sx - p.r, s.sx + p.r)
      ys += (s.sy - p.r, s.sy + p.r)
    } else if p.kind == "face" {
      for q in p.pts {
        let s = scenery.project(cam, q)
        xs.push(s.sx); ys.push(s.sy)
      }
    } else if p.kind == "label" {
      // sits on a sphere center: already inside that sphere's bbox
    } else {
      let sa = scenery.project(cam, p.a)
      let sb = scenery.project(cam, p.b)
      xs += (sa.sx, sb.sx); ys += (sa.sy, sb.sy)
    }
  }

  let elements = ()
  for a in shown {
    if a.element not in elements { elements.push(a.element) }
  }
  (
    prims: prims,
    bbox: (calc.min(..xs), calc.min(..ys), calc.max(..xs), calc.max(..ys)),
    elements: elements,
    element-colors: elements.map(color-of),
    camera: cam,
  )
}

// --- coverage suppression (screen-space pre-filter) -------------------------

/// Screen `(sx, sy)` of a 3D point under `cam`.
#let _proj2(cam, p) = { let q = scenery.project(cam, p); (q.sx, q.sy) }

/// Camera depth of a 3D point under `cam`.
#let _pdepth(cam, p) = scenery.project(cam, p).depth

/// Midpoint of two points.
#let _mid(a, b) = scenery.lerp(a, b, 0.5)

/// Squared distance from screen point `q` to segment `a`-`b` (all 2D).
#let _dist2-point-seg(q, a, b) = {
  let (qx, qy) = (q.at(0), q.at(1))
  let (ax, ay) = (a.at(0), a.at(1))
  let (bx, by) = (b.at(0), b.at(1))
  let (ux, uy) = (bx - ax, by - ay)
  let len2 = ux * ux + uy * uy
  let t = if len2 == 0 { 0.0 } else {
    calc.min(1.0, calc.max(0.0, ((qx - ax) * ux + (qy - ay) * uy) / len2))
  }
  let (dx, dy) = (qx - (ax + t * ux), qy - (ay + t * uy))
  dx * dx + dy * dy
}

/// Whether screen point `q` lies inside the disk of center `c`, radius `r`.
#let _in-disk(q, c, r) = {
  let (dx, dy) = (q.at(0) - c.at(0), q.at(1) - c.at(1))
  dx * dx + dy * dy < r * r
}

/// Drops the bond segs / cell edges the old renderer would have hidden under
/// sphere coverage, then returns the surviving primitives in their original
/// order (so the stable depth-sort tie-break is preserved).
///
/// Ports `render.typ`'s `seg-hidden`/`edge-hidden` verbatim into screen space,
/// with the SAME slacks (`2*r`, `0.45*w`). All spheres and all (unfiltered) segs
/// participate in the coverage test, exactly as the old draw loop did.
#let occlude(prims, cam) = {
  let spheres = prims.filter(p => p.kind == "sphere").map(p => (
    c: _proj2(cam, p.center), r: p.r, depth: _pdepth(cam, p.center),
  ))
  let segs = prims.filter(p => p.kind == "seg").map(p => (
    a: _proj2(cam, p.a), b: _proj2(cam, p.b), w: p.w, depth: _pdepth(cam, _mid(p.a, p.b)),
  ))
  // A bond stub is hidden when it projects fully inside a sphere's disk and is
  // not clearly in front of that sphere (2r slack).
  let seg-hidden(sa, sb, sd) = spheres.any(sp =>
    _in-disk(sa, sp.c, sp.r) and _in-disk(sb, sp.c, sp.r) and sd < sp.depth + 2 * sp.r)
  // A point is covered when a sphere disk or a bond stroke sits over it and is
  // not clearly behind it.
  let covered(q, ed) = spheres.any(sp =>
    _in-disk(q, sp.c, sp.r) and ed < sp.depth + sp.r
  ) or segs.any(b =>
    _dist2-point-seg(q, b.a, b.b) < calc.pow(0.45 * b.w, 2) and ed < b.depth + 1.0)

  prims.filter(p => {
    if p.kind == "seg" {
      let sd = _pdepth(cam, _mid(p.a, p.b))
      not seg-hidden(_proj2(cam, p.a), _proj2(cam, p.b), sd)
    } else if p.kind == "edge" {
      let ed = _pdepth(cam, _mid(p.a, p.b))
      not (covered(_proj2(cam, p.a), ed) and covered(_proj2(cam, p.b), ed))
    } else { true }
  })
}

// --- rendering --------------------------------------------------------------

/// Raw cetz draw commands for `scene` at canvas scale `scale` (for composition
/// inside a user `cetz.canvas`). Suppression is applied first; drawing goes
/// through scenery's `scene-group`.
#let draw-scene(scene, scale: 1.0) = {
  let filtered = occlude(scene.prims, scene.camera)
  scenery.scene-group(scenery.build-scene(..filtered), scene.camera, unit: scale)
}

/// Render a scene to content: a cetz canvas scaled so the scene's (screen-space)
/// bbox width equals `width`. `legend: true` adds element swatch rows to the
/// right; `axes-info: (vectors, view, n-axes?)` adds an a/b/c triad bottom-left.
/// Placement mirrors the old `render.typ` exactly (wyckoff's bbox, not scenery's
/// 3D-AABB projection), so output is pixel-identical.
#let render(scene, width: 8cm, legend: true, axes-info: none) = {
  let (x0, y0, x1, y1) = scene.bbox
  let s = (width / 1cm) / (x1 - x0)
  let cam = scene.camera
  let filtered = occlude(scene.prims, cam)
  let sub = scenery.build-scene(..filtered)
  cetz.canvas(length: 1cm, {
    scenery.scene-group(sub, cam, unit: s)
    if legend {
      let legend-colors = scene.at(
        "element-colors",
        default: scene.elements.map(el => element-info(el).color),
      )
      scenery.legend(
        scene.elements.zip(legend-colors),
        origin: (x1 * s + 0.7, y1 * s),
        gap: 0.14,
      )
    }
    if axes-info != none {
      let acam = scenery.camera(
        azimuth: axes-info.view.at("azimuth", default: 25deg),
        elevation: axes-info.view.at("elevation", default: 15deg),
      )
      let naxes = axes-info.at("n-axes", default: 3)
      scenery.axes-triad(
        acam,
        axes-info.vectors.slice(0, naxes),
        names: ("a", "b", "c").slice(0, naxes),
        origin: (x0 * s - 0.5, y0 * s - 0.5),
      )
    }
  })
}
