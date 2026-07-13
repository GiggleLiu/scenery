//! Line-clipping — the exact mirror of `scenery/src/render.typ`'s `_clip-lines`
//! and every helper it uses (`scenery/src/render.typ:125-485`). Each fn below
//! cites the source lines it transcribes; expression association and fold order
//! are preserved so the produced fragments are bit-identical to the pure-Typst
//! path. Trig never appears here: cameras cross the boundary as precomputed
//! cos/sin coefficients (see `schema::Camera`), and `camera_depth_direction`
//! reuses them, exactly like `camera.rs`.
//!
//! Scope note (brief): `_prepare-faces` (render.typ:158-189) is NOT mirrored —
//! the Typst caller runs it before serializing (it needs `resolve-style` for the
//! cull policy and opacity), so the prims arriving here are already prepared and
//! carry the `opaque` flag directly.
use crate::camera::Proj;
use crate::schema::{Camera, Prim};

// --- minimal 3-vector helpers (mirror of `scenery/src/linalg.typ`) -----------

/// `vsub` (linalg.typ:14): component-wise `a - b`.
fn vsub(a: [f64; 3], b: [f64; 3]) -> [f64; 3] {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}

/// `vdot` (linalg.typ:26): `sum(a_i * b_i)`. The `.sum()` folds left from the
/// first product, i.e. `((a0*b0) + a1*b1) + a2*b2`.
fn vdot(a: [f64; 3], b: [f64; 3]) -> f64 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

/// `vcross` (linalg.typ:32-36): the standard 3-vector cross product with the
/// exact component association Typst uses.
fn vcross(a: [f64; 3], b: [f64; 3]) -> [f64; 3] {
    [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]
}

/// `vlen` (linalg.typ:41): `sqrt(vdot(a, a))` (sqrt is exactly rounded).
fn vlen(a: [f64; 3]) -> f64 {
    vdot(a, a).sqrt()
}

/// `_lerp-point` (render.typ:293) via `lerp` (linalg.typ:59):
/// `vadd(vscale(a, 1 - t), vscale(b, t))` = `a_i*(1 - t) + b_i*t` per component,
/// same order (scale-then-add). IEEE-exact at t=0 and t=1.
fn lerp_point(a: [f64; 3], b: [f64; 3], t: f64) -> [f64; 3] {
    [
        a[0] * (1.0 - t) + b[0] * t,
        a[1] * (1.0 - t) + b[1] * t,
        a[2] * (1.0 - t) + b[2] * t,
    ]
}

// --- camera depth direction (mirror of render.typ:114-120) -------------------

/// `_camera-depth-direction` (render.typ:114-120): `(0,0,1)` for 2d; otherwise
/// `(-sin(az)*cos(el), cos(az)*cos(el), sin(el))` from the shipped coefficients.
fn camera_depth_direction(cam: &Camera) -> [f64; 3] {
    match cam {
        Camera::Flat => [0.0, 0.0, 1.0],
        Camera::Ortho { cos_az, sin_az, cos_el, sin_el }
        | Camera::Persp { cos_az, sin_az, cos_el, sin_el, .. } => {
            [-sin_az * cos_el, cos_az * cos_el, *sin_el]
        }
    }
}

// --- interval / quadratic math -----------------------------------------------

/// `_quadratic-interval` (render.typ:194-206): the interval in [0,1] where
/// `a t^2 + b t + c <= 0`. Keeps the `a == 0` and `disc <= 0` early-outs; `sqrt`
/// is exactly rounded.
fn quadratic_interval(a: f64, b: f64, c: f64) -> Option<(f64, f64)> {
    if a == 0.0 {
        if c <= 0.0 {
            Some((0.0, 1.0))
        } else {
            None
        }
    } else {
        let disc = b * b - 4.0 * a * c;
        if disc <= 0.0 {
            None
        } else {
            let root = disc.sqrt();
            let lo = f64::max(0.0, (-b - root) / (2.0 * a));
            let hi = f64::min(1.0, (-b + root) / (2.0 * a));
            if hi > lo {
                Some((lo, hi))
            } else {
                None
            }
        }
    }
}

/// `_depth-half` (render.typ:210-227): restrict an interval to the half-line
/// where `h(t) = h0 + dh*t` is in front of (`front`) or behind the sphere-centre
/// plane. Mirrors the `dh == 0` branch with exact `==`.
fn depth_half(interval: Option<(f64, f64)>, h0: f64, dh: f64, front: bool) -> Option<(f64, f64)> {
    let (mut lo, mut hi) = match interval {
        Some(iv) => iv,
        None => return None,
    };
    if dh == 0.0 {
        let keep = if front { h0 >= 0.0 } else { h0 <= 0.0 };
        if keep {
            Some((lo, hi))
        } else {
            None
        }
    } else {
        let cross = -h0 / dh;
        if front {
            if dh > 0.0 {
                lo = f64::max(lo, cross);
            } else {
                hi = f64::min(hi, cross);
            }
        } else if dh > 0.0 {
            hi = f64::min(hi, cross);
        } else {
            lo = f64::max(lo, cross);
        }
        if hi > lo {
            Some((lo, hi))
        } else {
            None
        }
    }
}

/// `_merge-intervals` (render.typ:272-291): sort by `lo` (stable `total_cmp`,
/// matching Typst's stable `.sorted(key:)`), then coalesce overlaps within
/// `eps = 1e-12` (dimensionless line parameters, so unit-independent).
fn merge_intervals(intervals: &[(f64, f64)]) -> Vec<(f64, f64)> {
    let eps = 1e-12;
    let mut sorted: Vec<(f64, f64)> = intervals.to_vec();
    sorted.sort_by(|x, y| x.0.total_cmp(&y.0));
    let mut merged: Vec<(f64, f64)> = Vec::new();
    for cur in sorted {
        if merged.is_empty() {
            merged.push(cur);
        } else {
            let prev = *merged.last().unwrap();
            if cur.0 <= prev.1 + eps {
                merged.pop();
                merged.push((prev.0, f64::max(prev.1, cur.1)));
            } else {
                merged.push(cur);
            }
        }
    }
    merged
}

// --- projected sphere occluder -----------------------------------------------

/// Screen-space occluder disk for a sphere — mirror of `_projected-sphere`
/// (render.typ:237-242): the sphere centre projected, with the silhouette radius
/// `sp.r * project-scale(cam, depth)` (exactly `sp.r` for orthographic/2d).
struct ProjSphere {
    sx: f64,
    sy: f64,
    depth: f64,
    r: f64,
}

fn projected_sphere(center: [f64; 3], r: f64, cam: &Camera) -> Result<ProjSphere, String> {
    let p = cam.project(center)?;
    let scale = cam.scale_at(p.depth)?;
    Ok(ProjSphere { sx: p.sx, sy: p.sy, depth: p.depth, r: r * scale })
}

/// `_overlap1` (render.typ:244): 1-D interval overlap test.
fn overlap1(a0: f64, a1: f64, b0: f64, b1: f64) -> bool {
    f64::min(a0, a1) <= f64::max(b0, b1) && f64::max(a0, a1) >= f64::min(b0, b1)
}

/// `_line-bbox-overlaps-disk` (render.typ:246-248).
fn line_bbox_overlaps_disk(pa: &Proj, pb: &Proj, sp: &ProjSphere) -> bool {
    overlap1(pa.sx, pb.sx, sp.sx - sp.r, sp.sx + sp.r)
        && overlap1(pa.sy, pb.sy, sp.sy - sp.r, sp.sy + sp.r)
}

/// `_line-sphere-occlusion` (render.typ:250-270): the hidden parameter intervals
/// (rear disk half + front ball half) and the full projected-disk interval.
/// Returns `(hidden, disk)` exactly.
fn line_sphere_occlusion(pa: &Proj, pb: &Proj, sp: &ProjSphere) -> (Vec<(f64, f64)>, Option<(f64, f64)>) {
    let (qx, qy) = (pa.sx - sp.sx, pa.sy - sp.sy);
    let (dx, dy) = (pb.sx - pa.sx, pb.sy - pa.sy);
    let h0 = pa.depth - sp.depth;
    let dh = pb.depth - pa.depth;
    let aa = dx * dx + dy * dy;
    let bb = 2.0 * (qx * dx + qy * dy);
    let cc = qx * qx + qy * qy - sp.r * sp.r;
    let disk = quadratic_interval(aa, bb, cc);
    let ball = quadratic_interval(aa + dh * dh, bb + 2.0 * h0 * dh, cc + h0 * h0);
    let mut hidden: Vec<(f64, f64)> = Vec::new();
    let rear = depth_half(disk, h0, dh, false);
    let front = depth_half(ball, h0, dh, true);
    if let Some(iv) = rear {
        hidden.push(iv);
    }
    if let Some(iv) = front {
        hidden.push(iv);
    }
    (hidden, disk)
}

// --- polygon / face occluder -------------------------------------------------

/// `_cross2` (render.typ:295): 2-D cross product `a.0*b.1 - a.1*b.0`.
fn cross2(a: (f64, f64), b: (f64, f64)) -> f64 {
    a.0 * b.1 - a.1 * b.0
}

/// `_point-in-polygon` (render.typ:297-312): even-odd ray-cast in screen space.
fn point_in_polygon(q: (f64, f64), pts: &[(f64, f64)]) -> bool {
    let mut inside = false;
    let mut j = pts.len() - 1;
    for i in 0..pts.len() {
        let pi = pts[i];
        let pj = pts[j];
        let crosses = (pi.1 > q.1) != (pj.1 > q.1);
        if crosses {
            let numerator = (pj.0 - pi.0) * (q.1 - pi.1);
            let x = numerator / (pj.1 - pi.1) + pi.0;
            if q.0 < x {
                inside = !inside;
            }
        }
        j = i;
    }
    inside
}

/// `_face-normal` (render.typ:125-142): the first non-degenerate cross product of
/// consecutive edges from the first vertex, or `None` when collinear. Per the
/// brief, the mesh-center reorientation (render.typ:137-140) is intentionally NOT
/// mirrored: the flag never crosses the boundary, and every plane-side use below
/// is orientation-invariant (numerator and denominator flip together).
fn face_normal(pts: &[[f64; 3]]) -> Option<[f64; 3]> {
    if pts.len() < 3 {
        return None;
    }
    let origin = pts[0];
    for i in 1..(pts.len() - 1) {
        let e1 = vsub(pts[i], origin);
        let e2 = vsub(pts[i + 1], origin);
        let n = vcross(e1, e2);
        let area_scale = vlen(e1) * vlen(e2);
        if area_scale > 0.0 && vlen(n) > 1e-12 * area_scale {
            return Some(n);
        }
    }
    None
}

/// Cached projected/planar data for one face occluder — mirror of
/// `_face-occluder` (render.typ:316-344). `opaque` comes from the schema flag
/// (already resolved Typst-side), not from `resolve-style`.
struct FaceOcc {
    origin: [f64; 3],
    normal: [f64; 3],
    view_dot: f64,
    scale: f64,
    screen: Vec<(f64, f64)>,
    bounds: (f64, f64, f64, f64), // (xmin, ymin, xmax, ymax)
    opaque: bool,
}

/// `calc.min(..xs)` over a non-empty slice — smallest value, earlier-wins on
/// ties. Only feeds the coarse bbox broad-phase, never emitted geometry.
fn min_all(xs: &[f64]) -> f64 {
    xs.iter().copied().fold(f64::INFINITY, |a, x| if x < a { x } else { a })
}
fn max_all(xs: &[f64]) -> f64 {
    xs.iter().copied().fold(f64::NEG_INFINITY, |a, x| if x > a { x } else { a })
}

fn face_occluder(pts: &[[f64; 3]], opaque: bool, cam: &Camera) -> Result<Option<FaceOcc>, String> {
    let normal = match face_normal(pts) {
        Some(n) => n,
        None => return Ok(None),
    };
    let origin = pts[0];
    let mut scale = 0.0f64;
    for q in pts {
        scale = f64::max(scale, vlen(vsub(*q, origin)));
    }
    let planar_eps = 1e-8 * vlen(normal) * scale;
    if pts.iter().any(|q| vdot(normal, vsub(*q, origin)).abs() > planar_eps) {
        return Ok(None);
    }
    let view_dot = vdot(normal, camera_depth_direction(cam));
    if view_dot.abs() <= 1e-12 * vlen(normal) {
        return Ok(None);
    }
    let mut screen: Vec<(f64, f64)> = Vec::with_capacity(pts.len());
    for q in pts {
        let s = cam.project(*q)?;
        screen.push((s.sx, s.sy));
    }
    let xs: Vec<f64> = screen.iter().map(|q| q.0).collect();
    let ys: Vec<f64> = screen.iter().map(|q| q.1).collect();
    let bounds = (min_all(&xs), min_all(&ys), max_all(&xs), max_all(&ys));
    Ok(Some(FaceOcc { origin, normal, view_dot, scale, screen, bounds, opaque }))
}

/// `_line-bbox-overlaps-face` (render.typ:346-349).
fn line_bbox_overlaps_face(pa: &Proj, pb: &Proj, face: &FaceOcc) -> bool {
    let b = face.bounds;
    overlap1(pa.sx, pb.sx, b.0, b.2) && overlap1(pa.sy, pb.sy, b.1, b.3)
}

/// `_line-face-interaction` (render.typ:353-401): projected-polygon cuts plus the
/// intervals an opaque face hides. Returns `(cuts, hidden)`. Translucent faces
/// contribute cuts only.
fn line_face_interaction(
    a: [f64; 3],
    b: [f64; 3],
    pa: &Proj,
    pb: &Proj,
    face: &FaceOcc,
) -> (Vec<f64>, Vec<(f64, f64)>) {
    let param_eps = 1e-12;
    let p0 = (pa.sx, pa.sy);
    let d = (pb.sx - pa.sx, pb.sy - pa.sy);
    let dlen = (d.0 * d.0 + d.1 * d.1).sqrt();
    let mut cuts: Vec<f64> = vec![0.0, 1.0];
    let n = face.screen.len();
    for i in 0..n {
        let q0 = face.screen[i];
        let q1 = face.screen[(i + 1) % n];
        let e = (q1.0 - q0.0, q1.1 - q0.1);
        let rel = (q0.0 - p0.0, q0.1 - p0.1);
        let den = cross2(d, e);
        let elen = (e.0 * e.0 + e.1 * e.1).sqrt();
        if dlen > 0.0 && elen > 0.0 && den.abs() > 1e-12 * dlen * elen {
            let t = cross2(rel, e) / den;
            let u = cross2(rel, d) / den;
            if t > param_eps && t < 1.0 - param_eps && u >= -param_eps && u <= 1.0 + param_eps {
                cuts.push(t);
            }
        }
    }
    let s0 = vdot(face.normal, vsub(a, face.origin));
    let s1 = vdot(face.normal, vsub(b, face.origin));
    if s0 * s1 < 0.0 {
        let t = s0 / (s0 - s1);
        if t > param_eps && t < 1.0 - param_eps {
            cuts.push(t);
        }
    }
    cuts.sort_by(|x, y| x.total_cmp(y));
    let mut unique: Vec<f64> = Vec::new();
    for t in cuts {
        if unique.is_empty() || t - *unique.last().unwrap() > param_eps {
            unique.push(t);
        }
    }
    let mut hidden: Vec<(f64, f64)> = Vec::new();
    if face.opaque {
        for i in 0..unique.len().saturating_sub(1) {
            let lo = unique[i];
            let hi = unique[i + 1];
            let mid = (lo + hi) / 2.0;
            let q = (p0.0 + d.0 * mid, p0.1 + d.1 * mid);
            if point_in_polygon(q, &face.screen) {
                let world = lerp_point(a, b, mid);
                let toward_viewer = -vdot(face.normal, vsub(world, face.origin)) / face.view_dot;
                let depth_eps = 1e-12 * f64::max(vlen(vsub(b, a)), face.scale);
                if toward_viewer > depth_eps {
                    hidden.push((lo, hi));
                }
            }
        }
    }
    (unique, hidden)
}

// --- fragment output ----------------------------------------------------------

/// Geometry a produced fragment carries back to the Typst reassembly step
/// (`engine.typ` `engine-sort`). A line fragment overrides the parent's
/// endpoints (and `head` for arrows); every other kind passes through untouched.
pub enum FragGeom {
    PassThrough,
    Line { a: [f64; 3], b: [f64; 3], head: Option<bool> },
}

/// One produced fragment, tagged with the index of its parent prim so the
/// Typst side can reattach styling. Multiple fragments may share one `i`.
pub struct Frag {
    pub i: usize,
    pub prim: FragGeom,
}

/// The (a, b) endpoints and arrow-ness of a line-like prim — mirror of
/// `_line-points` (render.typ:403): arrows use (from, to), others (a, b).
fn line_of(p: &Prim) -> Option<([f64; 3], [f64; 3], bool)> {
    match p {
        Prim::Seg { a, b, .. } => Some((*a, *b, false)),
        Prim::Edge { a, b } => Some((*a, *b, false)),
        Prim::Arrow { a, b } => Some((*a, *b, true)),
        _ => None,
    }
}

/// `_clip-lines` (render.typ:424-485). Splits seg/edge/arrow prims into the
/// portions visible around opaque spheres and faces, emitting fragments in
/// ascending-interval order at the parent's position; non-line prims pass
/// through. `_prepare-faces` is NOT re-run here (the caller already prepared the
/// prims — see the module note); every other line of the algorithm is mirrored
/// expression-for-expression.
pub fn clip_lines(prims: &[Prim], cam: &Camera) -> Result<Vec<Frag>, String> {
    let eps = 1e-12; // dimensionless parameter-space tolerance
    let mut spheres: Vec<ProjSphere> = Vec::new();
    for p in prims {
        if let Prim::Sphere { c, r } = p {
            spheres.push(projected_sphere(*c, *r, cam)?);
        }
    }
    let mut faces: Vec<FaceOcc> = Vec::new();
    for p in prims {
        if let Prim::Face { pts, opaque } = p {
            if let Some(f) = face_occluder(pts, *opaque, cam)? {
                faces.push(f);
            }
        }
    }
    let mut out: Vec<Frag> = Vec::new();
    for (i, p) in prims.iter().enumerate() {
        let (a, b, is_arrow) = match line_of(p) {
            Some(l) => l,
            None => {
                out.push(Frag { i, prim: FragGeom::PassThrough });
                continue;
            }
        };
        let pa = cam.project(a)?;
        let pb = cam.project(b)?;
        let mut hidden: Vec<(f64, f64)> = Vec::new();
        let mut cuts: Vec<f64> = vec![0.0, 1.0];
        for sp in &spheres {
            if !line_bbox_overlaps_disk(&pa, &pb, sp) {
                continue;
            }
            let (occ_hidden, occ_disk) = line_sphere_occlusion(&pa, &pb, sp);
            hidden.extend(occ_hidden);
            // Split even a fully visible line where it enters/leaves the disk so
            // the overlapping foreground piece gets its own depth key.
            if let Some(dk) = occ_disk {
                cuts.push(dk.0);
                cuts.push(dk.1);
            }
        }
        for face in &faces {
            if !line_bbox_overlaps_face(&pa, &pb, face) {
                continue;
            }
            let (hit_cuts, hit_hidden) = line_face_interaction(a, b, &pa, &pb, face);
            cuts.extend(hit_cuts);
            hidden.extend(hit_hidden);
        }
        let merged = merge_intervals(&hidden);
        for iv in &merged {
            cuts.push(iv.0);
            cuts.push(iv.1);
        }
        cuts.sort_by(|x, y| x.total_cmp(y));
        let mut unique: Vec<f64> = Vec::new();
        for t in cuts {
            if unique.is_empty() || t - *unique.last().unwrap() > eps {
                unique.push(t);
            }
        }
        let mut visible: Vec<(f64, f64)> = Vec::new();
        let mut hidden_index = 0usize;
        for k in 0..unique.len().saturating_sub(1) {
            let iv = (unique[k], unique[k + 1]);
            let mid = (iv.0 + iv.1) / 2.0;
            while hidden_index < merged.len() && merged[hidden_index].1 <= mid {
                hidden_index += 1;
            }
            let is_hidden = if hidden_index < merged.len() {
                let h = merged[hidden_index];
                mid > h.0 && mid < h.1
            } else {
                false
            };
            if iv.1 - iv.0 > eps && !is_hidden {
                visible.push(iv);
            }
        }
        for iv in &visible {
            // `_line-fragment` (render.typ:405-416): endpoints via lerp (exact at
            // 0/1); an arrow's head survives only on the fragment reaching t=1.
            let head = if is_arrow { Some(iv.1 >= 1.0 - eps) } else { None };
            let fa = lerp_point(a, b, iv.0);
            let fb = lerp_point(a, b, iv.1);
            out.push(Frag { i, prim: FragGeom::Line { a: fa, b: fb, head } });
        }
    }
    Ok(out)
}
