//! BSP splitting of INTERSECTING translucent faces (S4 Task 5, issue #33).
//!
//! The painter's algorithm keys each translucent face on a single centroid
//! depth, so two polyhedra that genuinely interpenetrate get a fixed front/back
//! order that is wrong on one side of the crossing. This module fixes that with
//! **pairwise mutual-plane splitting**: on each connected component of faces that
//! ACTUALLY intersect, every face is split by the planes of the partners whose
//! polygons cut through it. After splitting, each fragment lies entirely on one
//! side of every partner plane it crossed, so the ordinary centroid depth-sort
//! (delegated back to `pipeline`) produces the correct interleaving.
//!
//! This is NOT a full BSP-tree traversal — mutual pairwise splitting that
//! satisfies #33's acceptance, with the ordering left to the existing sort.
//!
//! DETERMINISM (the whole engine is deterministic — Universe requires it):
//! - candidates are processed in ascending ORIGINAL index everywhere;
//! - components are discovered by ascending lowest index, BFS over ascending
//!   neighbours;
//! - within a component, partition planes are applied in ascending index and the
//!   NEGATIVE-side piece is emitted first (the emission tie-break);
//! - no HashMap iteration, no libm — only `+ - * / sqrt` on the shipped data.
use crate::clip::{cross2, face_normal, lerp_point, point_in_polygon, vdot, vlen, vsub};
use crate::schema::Prim;

/// One translucent-face fragment: the source prim index it reattaches to, its
/// polygon ring, and whether it was actually split (only split fragments carry
/// `pts: Some(..)` back to Typst; unsplit ones reassemble bit-identically).
#[derive(Debug, Clone)]
pub struct FaceFrag {
    pub i: usize,
    pub pts: Vec<[f64; 3]>,
    pub split: bool,
}

/// A face's supporting plane: UNIT normal + origin (first vertex) + `scale` (max
/// vertex distance from the origin, the length yardstick for all tolerances).
struct Plane {
    n: [f64; 3],
    o: [f64; 3],
    scale: f64,
}

/// The plane of a candidate polygon. `None` when the polygon is degenerate
/// (collinear / <3 vertices) — such faces are never candidates.
fn plane_of(pts: &[[f64; 3]]) -> Option<Plane> {
    let raw = face_normal(pts)?;
    let l = vlen(raw);
    if l <= 0.0 {
        return None;
    }
    let n = [raw[0] / l, raw[1] / l, raw[2] / l];
    let o = pts[0];
    let mut scale = 0.0f64;
    for q in pts {
        scale = f64::max(scale, vlen(vsub(*q, o)));
    }
    Some(Plane { n, o, scale })
}

/// Signed (Euclidean) distance of `q` from a unit-normal plane.
fn signed_dist(pl: &Plane, q: [f64; 3]) -> f64 {
    vdot(pl.n, vsub(q, pl.o))
}

/// Is this prim a BSP candidate? Translucent, ≥3 vertices, planar (reuse
/// `face_occluder`'s planarity test: eps `1e-8·|n|·scale`, here with a unit
/// normal so eps is `1e-8·scale`) and a non-degenerate normal. Everything else
/// (opaque faces, non-faces, non-planar faces) passes through untouched.
fn is_candidate(prim: &Prim) -> bool {
    let (pts, opaque) = match prim {
        Prim::Face { pts, opaque } => (pts, *opaque),
        _ => return false,
    };
    if opaque {
        return false;
    }
    let pl = match plane_of(pts) {
        Some(p) => p,
        None => return false,
    };
    let planar_eps = 1e-8 * pl.scale; // |n| == 1
    !pts.iter().any(|q| signed_dist(&pl, *q).abs() > planar_eps)
}

/// Collect the translucent-face candidates in ascending prim index. Each starts
/// life as an unsplit fragment tagged with its source index.
pub fn collect_candidates(prims: &[Prim]) -> Vec<FaceFrag> {
    let mut out = Vec::new();
    for (i, p) in prims.iter().enumerate() {
        if is_candidate(p) {
            if let Prim::Face { pts, .. } = p {
                out.push(FaceFrag { i, pts: pts.clone(), split: false });
            }
        }
    }
    out
}

/// An in-plane orthonormal basis `(u, v)` for `pl`, so a 3D point projects to 2D
/// coordinates `((q-o)·u, (q-o)·v)` WITHIN the plane (this is the polygon's own
/// plane, NOT the camera screen). Used for the chord/polygon 2D containment test.
fn plane_basis(pts: &[[f64; 3]], pl: &Plane) -> ([f64; 3], [f64; 3]) {
    // A reference in-plane direction: the first edge long enough to trust.
    let mut u = [0.0, 0.0, 0.0];
    for q in pts.iter().skip(1) {
        let e = vsub(*q, pl.o);
        let l = vlen(e);
        if l > 1e-12 * f64::max(pl.scale, 1.0) {
            u = [e[0] / l, e[1] / l, e[2] / l];
            break;
        }
    }
    // v = n × u (already unit, since n ⟂ u and both unit).
    let n = pl.n;
    let v = [
        n[1] * u[2] - n[2] * u[1],
        n[2] * u[0] - n[0] * u[2],
        n[0] * u[1] - n[1] * u[0],
    ];
    (u, v)
}

fn to_2d(pl: &Plane, u: [f64; 3], v: [f64; 3], q: [f64; 3]) -> (f64, f64) {
    let d = vsub(q, pl.o);
    (vdot(d, u), vdot(d, v))
}

/// The crossing points where polygon `g` pierces plane `pl` — one per edge whose
/// endpoints sit on strictly opposite sides (beyond `eps`).
fn plane_crossings(g: &[[f64; 3]], pl: &Plane, eps: f64) -> Vec<[f64; 3]> {
    let m = g.len();
    let mut pts = Vec::new();
    for k in 0..m {
        let a = g[k];
        let b = g[(k + 1) % m];
        let da = signed_dist(pl, a);
        let db = signed_dist(pl, b);
        if (da > eps && db < -eps) || (da < -eps && db > eps) {
            let t = da / (da - db);
            pts.push(lerp_point(a, b, t));
        }
    }
    pts
}

/// Do two 2D segments properly cross (strict interior crossing)? Orientation via
/// `cross2`, mirroring the sign tests used elsewhere in the engine.
fn segments_cross(p1: (f64, f64), p2: (f64, f64), p3: (f64, f64), p4: (f64, f64)) -> bool {
    let sub = |a: (f64, f64), b: (f64, f64)| (a.0 - b.0, a.1 - b.1);
    let d1 = cross2(sub(p4, p3), sub(p1, p3));
    let d2 = cross2(sub(p4, p3), sub(p2, p3));
    let d3 = cross2(sub(p2, p1), sub(p3, p1));
    let d4 = cross2(sub(p2, p1), sub(p4, p1));
    ((d1 > 0.0 && d2 < 0.0) || (d1 < 0.0 && d2 > 0.0))
        && ((d3 > 0.0 && d4 < 0.0) || (d3 < 0.0 && d4 > 0.0))
}

/// `faces_intersect(f, g)` — does `g`'s polygon genuinely interpenetrate `f`?
/// (i) `g` has vertices strictly on BOTH sides of `plane(f)`; and (ii) the chord
/// `plane(f) ∩ polygon(g)` intersects `polygon(f)` (2D test in f's plane: either
/// chord endpoint inside `polygon(f)`, or a proper chord/edge crossing). Both ⇒
/// the polygons interpenetrate. Directional; the caller ORs both orders for the
/// intersection graph, and drives per-partner splitting with the one-way form.
fn faces_intersect(f: &[[f64; 3]], pf: &Plane, g: &[[f64; 3]], pg: &Plane) -> bool {
    let eps = 1e-9 * f64::max(pf.scale, pg.scale);
    // (i) g straddles plane(f).
    let mut has_pos = false;
    let mut has_neg = false;
    for q in g {
        let d = signed_dist(pf, *q);
        if d > eps {
            has_pos = true;
        } else if d < -eps {
            has_neg = true;
        }
    }
    if !(has_pos && has_neg) {
        return false;
    }
    // (ii) chord = plane(f) ∩ polygon(g); the two extreme crossing points.
    let crossings = plane_crossings(g, pf, eps);
    if crossings.len() < 2 {
        return false;
    }
    let (mut i0, mut i1, mut best) = (0usize, 1usize, -1.0f64);
    for a in 0..crossings.len() {
        for b in (a + 1)..crossings.len() {
            let d2 = vlen(vsub(crossings[a], crossings[b]));
            if d2 > best {
                best = d2;
                i0 = a;
                i1 = b;
            }
        }
    }
    if best <= eps {
        return false;
    }
    // Project the chord and polygon(f) into f's own plane and test containment.
    let (u, v) = plane_basis(f, pf);
    let poly2: Vec<(f64, f64)> = f.iter().map(|q| to_2d(pf, u, v, *q)).collect();
    let c0 = to_2d(pf, u, v, crossings[i0]);
    let c1 = to_2d(pf, u, v, crossings[i1]);
    // Endpoint- OR midpoint-inside. The midpoint is what gives the test teeth on
    // the through-and-through case where the chord endpoints land exactly on
    // polygon(f)'s boundary (e.g. two quads of equal extent crossing along the
    // x-axis — the #33 acceptance scene): there the endpoints are on the boundary
    // (never counted "inside") and the crossings are not "proper", yet the chord
    // clearly passes through f's interior, where its midpoint sits.
    let cmid = ((c0.0 + c1.0) * 0.5, (c0.1 + c1.1) * 0.5);
    if point_in_polygon(c0, &poly2)
        || point_in_polygon(c1, &poly2)
        || point_in_polygon(cmid, &poly2)
    {
        return true;
    }
    let n = poly2.len();
    for k in 0..n {
        if segments_cross(c0, c1, poly2[k], poly2[(k + 1) % n]) {
            return true;
        }
    }
    false
}

/// Split polygon `g` by plane `pl` into (negative-side, positive-side) pieces.
/// On-plane vertices (|d| ≤ eps) join both rings; each strictly-crossing edge
/// contributes an interpolated vertex `t = d0/(d0-d1)` to both rings.
fn split_polygon(g: &[[f64; 3]], pl: &Plane, eps: f64) -> (Vec<[f64; 3]>, Vec<[f64; 3]>) {
    let m = g.len();
    let ds: Vec<f64> = g.iter().map(|q| signed_dist(pl, *q)).collect();
    let mut neg: Vec<[f64; 3]> = Vec::new();
    let mut pos: Vec<[f64; 3]> = Vec::new();
    for k in 0..m {
        let cur = g[k];
        let dc = ds[k];
        let dn = ds[(k + 1) % m];
        if dc.abs() <= eps {
            neg.push(cur);
            pos.push(cur);
        } else if dc > 0.0 {
            pos.push(cur);
        } else {
            neg.push(cur);
        }
        if (dc > eps && dn < -eps) || (dc < -eps && dn > eps) {
            let t = dc / (dc - dn);
            let ip = lerp_point(cur, g[(k + 1) % m], t);
            neg.push(ip);
            pos.push(ip);
        }
    }
    (neg, pos)
}

/// Squared area of a planar polygon (Newell's method): `|½ Σ vₖ × vₖ₊₁|²`.
fn area_sq(pts: &[[f64; 3]]) -> f64 {
    let m = pts.len();
    let mut acc = [0.0f64, 0.0, 0.0];
    for k in 0..m {
        let a = pts[k];
        let b = pts[(k + 1) % m];
        acc[0] += a[1] * b[2] - a[2] * b[1];
        acc[1] += a[2] * b[0] - a[0] * b[2];
        acc[2] += a[0] * b[1] - a[1] * b[0];
    }
    0.25 * vdot(acc, acc)
}

/// A polygon is renderable if it has ≥3 vertices and non-sliver area.
fn keep_piece(pts: &[[f64; 3]], eps: f64, scale: f64) -> bool {
    let thresh = eps * scale;
    pts.len() >= 3 && area_sq(pts) > thresh * thresh
}

/// Split all INTERSECTING translucent faces before depth ordering (issue #33).
///
/// `faces` are the candidate fragments in ascending source index. Builds the
/// undirected intersection graph, takes connected components (ascending
/// discovery + BFS), and within each multi-face component splits every fragment
/// by the planes of the partners whose polygons cut through it. Size-1
/// components pass through untouched (`split: false` — the negative control).
/// Returns the (possibly larger) fragment list; each still tagged with its
/// source index, `split` set only where a cut actually happened.
pub fn split_translucent(faces: Vec<FaceFrag>) -> Vec<FaceFrag> {
    let n = faces.len();
    if n < 2 {
        return faces;
    }
    // Precompute each candidate's plane (candidates are guaranteed planar).
    let planes: Vec<Plane> = faces
        .iter()
        .map(|f| plane_of(&f.pts).expect("candidate face is planar"))
        .collect();

    // Undirected intersection graph. Edge iff the polygons interpenetrate in
    // EITHER order (ORing avoids missing a real crossing; a spurious edge is
    // harmless because the per-partner split predicate below still has teeth).
    let mut adj: Vec<Vec<usize>> = vec![Vec::new(); n];
    for a in 0..n {
        for b in (a + 1)..n {
            let ab = faces_intersect(&faces[a].pts, &planes[a], &faces[b].pts, &planes[b]);
            let ba = faces_intersect(&faces[b].pts, &planes[b], &faces[a].pts, &planes[a]);
            if ab || ba {
                adj[a].push(b);
                adj[b].push(a);
            }
        }
    }

    // Connected components, discovered by ascending lowest index, BFS over
    // ascending neighbours (deterministic order).
    let mut comp = vec![usize::MAX; n];
    let mut components: Vec<Vec<usize>> = Vec::new();
    for start in 0..n {
        if comp[start] != usize::MAX {
            continue;
        }
        let cid = components.len();
        let mut queue = std::collections::VecDeque::new();
        queue.push_back(start);
        comp[start] = cid;
        let mut members = Vec::new();
        while let Some(x) = queue.pop_front() {
            members.push(x);
            for &y in &adj[x] {
                if comp[y] == usize::MAX {
                    comp[y] = cid;
                    queue.push_back(y);
                }
            }
        }
        members.sort_unstable(); // ascending index within the component
        components.push(members);
    }

    // Output preserves ascending source-index order: process components, but
    // write each candidate's resulting pieces into a per-candidate slot so the
    // final list is grouped by ascending source index (matching prim order).
    let mut result_slots: Vec<Vec<FaceFrag>> = Vec::with_capacity(n);
    for f in &faces {
        result_slots.push(vec![f.clone()]);
    }

    for members in &components {
        if members.len() < 2 {
            continue; // isolated face: untouched (split stays false)
        }
        // Partition faces p in ascending index; each splits the CURRENT
        // fragments of the OTHER member faces by plane(p).
        for &p in members {
            let pl_p = &planes[p];
            let poly_p = &faces[p].pts;
            for &g in members {
                if g == p {
                    continue;
                }
                let eps = 1e-9 * f64::max(pl_p.scale, planes[g].scale);
                let mut next: Vec<FaceFrag> = Vec::new();
                for frag in std::mem::take(&mut result_slots[g]) {
                    // A split fragment stays coplanar with its parent face, so it
                    // shares `planes[g]` (used only as the scale yardstick here).
                    if plane_of(&frag.pts).is_none() {
                        next.push(frag);
                        continue;
                    }
                    // Split only where plane(p) genuinely cuts THROUGH this
                    // fragment (one-way predicate: strict straddle + chord in p).
                    if !faces_intersect(poly_p, pl_p, &frag.pts, &planes[g]) {
                        next.push(frag);
                        continue;
                    }
                    let (neg, pos) = split_polygon(&frag.pts, pl_p, eps);
                    let keep_neg = keep_piece(&neg, eps, planes[g].scale);
                    let keep_pos = keep_piece(&pos, eps, planes[g].scale);
                    if keep_neg && keep_pos {
                        // Negative-side piece FIRST (deterministic emission).
                        next.push(FaceFrag { i: frag.i, pts: neg, split: true });
                        next.push(FaceFrag { i: frag.i, pts: pos, split: true });
                    } else {
                        // No genuine two-way cut: keep the fragment unchanged.
                        next.push(frag);
                    }
                }
                result_slots[g] = next;
            }
        }
    }

    let mut out = Vec::new();
    for slot in result_slots {
        out.extend(slot);
    }
    out
}
