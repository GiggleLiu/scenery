//! The depth-sort pipeline — the exact mirror of `render.typ`'s depth-key
//! computation and `sort-prims` stable ordering. Task 2 scope: depth keys +
//! stable sort only (no cull / clip / bsp yet — those land in T3/T5). The
//! primitives arriving here are already `_prepare-faces` output (meshes
//! exploded, culling applied) on the Typst side, so this module never sees a
//! mesh: it keys each primitive by a single 3-point's camera depth.
use crate::schema::{OutRec, Prim, Request};

/// Midpoint of two points — mirror of `render.typ:70` `_mid`:
/// `vscale(vadd(a, b), 0.5)`, i.e. `(a + b) * 0.5` component-wise.
fn mid(a: [f64; 3], b: [f64; 3]) -> [f64; 3] {
    [(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5, (a[2] + b[2]) * 0.5]
}

/// Centroid of a point array — mirror of `render.typ:73` `_centroid`:
/// `vscale(pts.fold((0,0,0), vadd), 1 / pts.len())`. The fold is LEFT
/// (accumulate `sum += p` in input order, starting from `(0,0,0)`), then each
/// summed component is multiplied by `s = 1.0 / n`. Operation order preserved
/// for bit-identical rounding.
fn centroid(pts: &[[f64; 3]]) -> [f64; 3] {
    let s = 1.0 / (pts.len() as f64);
    let mut sum = [0.0f64, 0.0, 0.0];
    for p in pts {
        sum[0] += p[0];
        sum[1] += p[1];
        sum[2] += p[2];
    }
    [sum[0] * s, sum[1] * s, sum[2] * s]
}

/// The 3D point whose camera depth is a primitive's depth key — mirror of
/// `render.typ:76-83` `_depth-point`: sphere → center, seg/edge/arrow →
/// midpoint, face → centroid. Labels never reach here (`run` keys them 1e9).
fn depth_point(p: &Prim) -> [f64; 3] {
    match p {
        Prim::Sphere { c, .. } => *c,
        Prim::Seg { a, b, .. } => mid(*a, *b),
        Prim::Edge { a, b } => mid(*a, *b),
        Prim::Arrow { a, b } => mid(*a, *b),
        Prim::Face { pts, .. } => centroid(pts),
        Prim::Label { p } => *p, // unreachable: labels handled before this
    }
}

/// Depth keys + stable back-to-front sort — mirror of `render.typ:499-507`
/// `sort-prims`. Label depth is the literal `1e9`; every other primitive
/// projects its depth point. Non-finite depth keys are an error. The stable
/// ascending sort by `total_cmp` mirrors Typst's stable `.sorted(key:)`,
/// preserving input order for ties.
pub fn run(req: &Request) -> Result<Vec<OutRec>, String> {
    let cam = &req.camera;
    let mut keyed: Vec<OutRec> = Vec::with_capacity(req.prims.len());
    for (i, p) in req.prims.iter().enumerate() {
        let d = match p {
            Prim::Label { .. } => 1e9,
            _ => cam.project(depth_point(p))?.depth,
        };
        if !d.is_finite() {
            return Err(format!(
                "scenery-engine: non-finite depth for primitive {i}"
            ));
        }
        keyed.push(OutRec { i, d, a: None, b: None, head: None, pts: None });
    }
    keyed.sort_by(|x, y| x.d.total_cmp(&y.d)); // stable, mirrors Typst .sorted(key:)
    Ok(keyed)
}
