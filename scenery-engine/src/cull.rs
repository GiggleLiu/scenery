//! Coverage-suppression cull — the exact mirror of materia `occlude`,
//! parameterized by the schema `Cull` slacks
//! so the policy crosses the CBOR boundary as NUMBERS, not code (the engine stays
//! host-agnostic). It is a screen-space pre-filter run FIRST in the pipeline: it
//! drops bond stubs (`seg`) fully hidden under a sphere disk, and cell edges
//! (`edge`) whose BOTH projected endpoints are covered by a sphere disk or a bond
//! stroke. Spheres, faces, arrows and labels always survive.
//!
//! All spheres and ALL segs act as occluders — the occluder lists are built
//! BEFORE any filtering (mirror of the pure path, where `occlude` builds its
//! `spheres`/`segs` lists over the unfiltered prims), so a seg that is itself
//! dropped still occludes edges. Survivors keep input order.
//!
//! Projection matches `camera.rs` exactly (only `+ - * / sqrt` on the shipped
//! trig coefficients), so the survivor set is bit-identical to the Typst path.
use crate::schema::{Camera, Cull, Prim};

/// A projected sphere occluder disk (mirror of `figure.typ:221-225`): centre in
/// screen units, silhouette radius `r * scale_at(depth)`, and the centre depth.
struct Disk {
    cx: f64,
    cy: f64,
    r: f64,
    depth: f64,
}

/// A projected seg occluder (mirror of `figure.typ:226-230`): both endpoints in
/// screen units, stroke width `w * scale_at(midpoint depth)`, and midpoint depth.
struct SegOcc {
    ax: f64,
    ay: f64,
    bx: f64,
    by: f64,
    w: f64,
    depth: f64,
}

/// `_mid` (figure.typ:191) → `lerp(a, b, 0.5)`: `(a + b) * 0.5` component-wise.
fn mid(a: [f64; 3], b: [f64; 3]) -> [f64; 3] {
    [(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5, (a[2] + b[2]) * 0.5]
}

/// `_in-disk` (figure.typ:208-211): strict `dx^2 + dy^2 < r^2`.
fn in_disk(qx: f64, qy: f64, cx: f64, cy: f64, r: f64) -> bool {
    let dx = qx - cx;
    let dy = qy - cy;
    dx * dx + dy * dy < r * r
}

/// `_dist2-point-seg` (figure.typ:194-205): squared distance from screen point
/// `q` to segment `a`-`b`, with the clamped-`t` projection and the same
/// expression association (the `len2 == 0` branch preserved with exact `==`).
fn dist2_point_seg(qx: f64, qy: f64, ax: f64, ay: f64, bx: f64, by: f64) -> f64 {
    let ux = bx - ax;
    let uy = by - ay;
    let len2 = ux * ux + uy * uy;
    let t = if len2 == 0.0 {
        0.0
    } else {
        f64::min(1.0, f64::max(0.0, ((qx - ax) * ux + (qy - ay) * uy) / len2))
    };
    let dx = qx - (ax + t * ux);
    let dy = qy - (ay + t * uy);
    dx * dx + dy * dy
}

/// Keep-mask over `prims` (parallel to `prims`, `true` = survives): the exact
/// mirror of `figure.typ`'s `occlude` filter. A `seg` is dropped iff some sphere
/// hides it (both endpoints inside the disk AND `sd < depth + seg_r_slack*r`); an
/// `edge` is dropped iff BOTH projected endpoints are `covered`; everything else
/// survives. `Err` propagates a projection failure (a point at/behind a
/// perspective camera), matching the Typst path's assert.
pub fn cull_mask(prims: &[Prim], cam: &Camera, cull: &Cull) -> Result<Vec<bool>, String> {
    // Occluder lists over the UNFILTERED prims (mirror of figure.typ:221-230).
    let mut disks: Vec<Disk> = Vec::new();
    for p in prims {
        if let Prim::Sphere { c, r } = p {
            let q = cam.project(*c)?;
            let scale = cam.scale_at(q.depth)?;
            disks.push(Disk { cx: q.sx, cy: q.sy, r: r * scale, depth: q.depth });
        }
    }
    let mut segs: Vec<SegOcc> = Vec::new();
    for p in prims {
        if let Prim::Seg { a, b, w } = p {
            let d = cam.project(mid(*a, *b))?.depth;
            let pa = cam.project(*a)?;
            let pb = cam.project(*b)?;
            let scale = cam.scale_at(d)?;
            segs.push(SegOcc { ax: pa.sx, ay: pa.sy, bx: pb.sx, by: pb.sy, w: w * scale, depth: d });
        }
    }

    // `seg-hidden` (figure.typ:233-234): both endpoints inside a disk and not
    // clearly in front of that sphere (`seg_r_slack` slack).
    let seg_hidden = |sax: f64, say: f64, sbx: f64, sby: f64, sd: f64| {
        disks.iter().any(|sp| {
            in_disk(sax, say, sp.cx, sp.cy, sp.r)
                && in_disk(sbx, sby, sp.cx, sp.cy, sp.r)
                && sd < sp.depth + cull.seg_r_slack * sp.r
        })
    };
    // `covered` (figure.typ:237-240): a sphere disk or a bond stroke sits over the
    // point and is not clearly behind it.
    let covered = |qx: f64, qy: f64, ed: f64| {
        disks.iter().any(|sp| {
            in_disk(qx, qy, sp.cx, sp.cy, sp.r) && ed < sp.depth + cull.point_r_slack * sp.r
        }) || segs.iter().any(|b| {
            let thr = cull.seg_w_frac * b.w;
            dist2_point_seg(qx, qy, b.ax, b.ay, b.bx, b.by) < thr * thr
                && ed < b.depth + cull.seg_d_slack
        })
    };

    // The filter (figure.typ:242-250): survivors keep input order.
    let mut keep = Vec::with_capacity(prims.len());
    for p in prims {
        let alive = match p {
            Prim::Seg { a, b, .. } => {
                let sd = cam.project(mid(*a, *b))?.depth;
                let pa = cam.project(*a)?;
                let pb = cam.project(*b)?;
                !seg_hidden(pa.sx, pa.sy, pb.sx, pb.sy, sd)
            }
            Prim::Edge { a, b } => {
                let ed = cam.project(mid(*a, *b))?.depth;
                let pa = cam.project(*a)?;
                let pb = cam.project(*b)?;
                !(covered(pa.sx, pa.sy, ed) && covered(pb.sx, pb.sy, ed))
            }
            _ => true,
        };
        keep.push(alive);
    }
    Ok(keep)
}
