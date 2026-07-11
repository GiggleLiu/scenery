#import "linalg.typ": vadd, vsub, vscale, vnorm, lerp
#import "data.typ": element-info
#import "geometry.typ": display-atoms, cell-edges, find-bonds, find-polyhedra
#import "project.typ": projector

/// Build a pure-data scene: projected primitives with depth keys, bbox, and
/// the deduplicated element list. No cetz here (the renderer is Task 12).
#let build-scene(
  structure,
  view: (azimuth: 25deg, elevation: 15deg),
  supercell: (1, 1, 1),
  bonds: auto,          // auto | none | rules array
  polyhedra: (),        // element list
  radius: 0.45,
  bond-width: 0.16,
  labels: false,
) = {
  let proj = projector(view)
  let shown = display-atoms(structure, supercell: supercell)
  let prims = ()

  let rdisp(el) = radius * element-info(el).r-atom
  for a in shown {
    let s = proj(a.cart)
    prims.push((kind: "sphere", c: (s.sx, s.sy), r: rdisp(a.element),
      color: element-info(a.element).color, element: a.element, depth: s.depth))
  }
  if labels {
    // depth 1e9 sorts labels after every geometric primitive: drawn last.
    for a in shown {
      let s = proj(a.cart)
      prims.push((kind: "label", at: (s.sx, s.sy), text: a.element, depth: 1e9))
    }
  }

  let blist = if bonds == none { () } else { find-bonds(shown, bonds) }
  for b in blist {
    let (pa, pb) = (shown.at(b.i), shown.at(b.j))
    let dir = vnorm(vsub(pb.cart, pa.cart))
    let a0 = vadd(pa.cart, vscale(dir, 0.9 * rdisp(pa.element)))
    let b0 = vsub(pb.cart, vscale(dir, 0.9 * rdisp(pb.element)))
    let mid = lerp(a0, b0, 0.5)
    for (p, q, el) in ((a0, mid, pa.element), (mid, b0, pb.element)) {
      let (sp, sq, sm) = (proj(p), proj(q), proj(lerp(p, q, 0.5)))
      prims.push((kind: "seg", a: (sp.sx, sp.sy), b: (sq.sx, sq.sy),
        color: element-info(el).color.darken(10%), w: bond-width, depth: sm.depth))
    }
  }

  if polyhedra.len() > 0 {
    for poly in find-polyhedra(shown, blist, polyhedra) {
      let col = element-info(shown.at(poly.center).element).color
      for f in poly.faces {
        let spts = f.map(p => proj(p))
        let cdepth = spts.map(s => s.depth).sum() / spts.len()
        prims.push((kind: "face", pts: spts.map(s => (s.sx, s.sy)), color: col, depth: cdepth - 0.01))
      }
    }
  }

  for (ea, eb) in cell-edges(structure, supercell: supercell) {
    for t in range(8) {
      let p = lerp(ea, eb, t / 8)
      let q = lerp(ea, eb, (t + 1) / 8)
      let sm = proj(lerp(p, q, 0.5))
      let (sp, sq) = (proj(p), proj(q))
      prims.push((kind: "edge", a: (sp.sx, sp.sy), b: (sq.sx, sq.sy), depth: sm.depth))
    }
  }

  let xs = ()
  let ys = ()
  for p in prims {
    if p.kind == "sphere" {
      xs += (p.c.at(0) - p.r, p.c.at(0) + p.r)
      ys += (p.c.at(1) - p.r, p.c.at(1) + p.r)
    } else if p.kind == "face" {
      xs += p.pts.map(q => q.at(0)); ys += p.pts.map(q => q.at(1))
    } else if p.kind == "label" {
      // sits on a sphere center: already inside the sphere's bbox
    } else {
      xs += (p.a.at(0), p.b.at(0)); ys += (p.a.at(1), p.b.at(1))
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
  )
}
