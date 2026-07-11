#import "@preview/cetz:0.5.2"
#import "data.typ": element-info
#import "project.typ": projector
#import "linalg.typ": vnorm

/// Radial "3D ball" fill: bright highlight up-left of center fading through
/// the base color to a darkened rim. Stops are (color, offset) pairs.
#let _sphere-fill(col) = gradient.radial(
  (color.mix((white, 70%), (col, 30%)), 0%),
  (color.mix((white, 25%), (col, 75%)), 25%),
  (col, 55%),
  (col.darken(30%), 100%),
  center: (35%, 30%),
  radius: 110%,
)

/// Emit cetz draw commands for a scene built by `build-scene`.
/// Primitives are depth-sorted ascending (far -> near) and painted
/// back-to-front; coordinates (in Angstrom) are multiplied by `scale`
/// (canvas units per Angstrom).
#let draw-scene(scene, scale: 1.0) = {
  // Bind before the wildcard import: cetz.draw exports a `scale` transform
  // that would otherwise shadow the parameter.
  let s = scale
  import cetz.draw: *
  let pt(p) = (p.at(0) * s, p.at(1) * s)
  // Painter's algorithm on projected 2D primitives cannot clip lines that
  // pierce a sphere and exit toward the viewer: they would be painted across
  // the sphere's face as scratches. Two cases need suppression:
  //  - bond halves pointing nearly at the viewer, foreshortened to a stub
  //    that projects fully inside their own atom's disk;
  //  - cell-edge sub-segments running through boundary atoms or collinear
  //    with boundary bonds (which would leave a thin stripe inside bonds).
  // Suppressing them makes lines visually terminate at surfaces, as in a
  // true 3D render. Depth grows toward the viewer; slacks are in Angstrom.
  let spheres = scene.prims.filter(p => p.kind == "sphere")
  let segs = scene.prims.filter(p => p.kind == "seg")
  let dist2-point-seg(q, a, b) = {
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
  let in-disk(q, sp) = {
    let (dx, dy) = (q.at(0) - sp.c.at(0), q.at(1) - sp.c.at(1))
    dx * dx + dy * dy < sp.r * sp.r
  }
  // A bond stub is hidden when it projects fully inside a sphere's disk and
  // is not clearly in front of that sphere (2r slack covers a bond midpoint
  // protruding from the sphere's own front hemisphere).
  let seg-hidden(e) = spheres.any(sp =>
    in-disk(e.a, sp) and in-disk(e.b, sp) and e.depth < sp.depth + 2 * sp.r)
  // An edge sub-segment is hidden when each endpoint is covered by a sphere
  // disk or lies within a bond's stroke, and the covering primitive is not
  // clearly behind it.
  let covered(q, e) = spheres.any(sp =>
    in-disk(q, sp) and e.depth < sp.depth + sp.r
  ) or segs.any(b =>
    dist2-point-seg(q, b.a, b.b) < calc.pow(0.45 * b.w, 2) and e.depth < b.depth + 1.0
  )
  let edge-hidden(e) = covered(e.a, e) and covered(e.b, e)
  for p in scene.prims.sorted(key: p => p.depth) {
    if p.kind == "face" {
      line(..p.pts.map(pt), close: true,
        fill: p.color.transparentize(55%),
        stroke: (paint: p.color.darken(35%), thickness: 0.5pt))
    } else if p.kind == "edge" {
      if not edge-hidden(p) {
        line(pt(p.a), pt(p.b), stroke: (paint: luma(120), thickness: 0.7pt))
      }
    } else if p.kind == "seg" {
      if not seg-hidden(p) {
        line(pt(p.a), pt(p.b),
          stroke: (paint: p.color, thickness: p.w * s * 1cm, cap: "round"))
      }
    } else if p.kind == "sphere" {
      circle(pt(p.c), radius: p.r * s,
        fill: _sphere-fill(p.color),
        stroke: (paint: p.color.darken(45%), thickness: 0.5pt))
    } else if p.kind == "label" {
      content(pt(p.at), text(size: 7pt, fill: black, weight: "bold", p.text))
    }
  }
}

/// Render a scene to content: a cetz canvas scaled so the scene's bbox
/// width equals `width`. `legend: true` adds element swatch rows right of
/// the bbox; `axes-info: (vectors, view, n-axes?)` adds an a/b/c triad of
/// the projected lattice directions below-left of the bbox (pass
/// `n-axes: 2` for layer structures to omit c).
#let render(scene, width: 8cm, legend: true, axes-info: none) = {
  let (x0, y0, x1, y1) = scene.bbox
  let s = (width / 1cm) / (x1 - x0)
  cetz.canvas(length: 1cm, {
    import cetz.draw: *
    draw-scene(scene, scale: s)
    if legend {
      for (i, el) in scene.elements.enumerate() {
        let y = y1 * s - i * 0.55
        circle((x1 * s + 0.7, y), radius: 0.16,
          fill: _sphere-fill(element-info(el).color),
          stroke: (paint: element-info(el).color.darken(45%), thickness: 0.4pt))
        content((x1 * s + 1.0, y), anchor: "west", text(size: 9pt, el))
      }
    }
    if axes-info != none {
      let proj = projector(axes-info.view)
      let names = ("a", "b", "c")
      let origin = (x0 * s - 0.5, y0 * s - 0.5)
      let naxes = axes-info.at("n-axes", default: 3)
      for i in range(naxes) {
        let d = proj(vnorm(axes-info.vectors.at(i)))
        let tip = (origin.at(0) + d.sx * 0.7, origin.at(1) + d.sy * 0.7)
        line(origin, tip, mark: (end: ">", fill: black), stroke: 0.7pt)
        content((origin.at(0) + d.sx * 0.95, origin.at(1) + d.sy * 0.95),
          text(size: 8pt, style: "italic", names.at(i)))
      }
    }
  })
}
