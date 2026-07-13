//! The depth-sort pipeline — the exact mirror of `render.typ`'s clip + depth-key
//! computation and `sort-prims` stable ordering, i.e. `sort-prims(_clip-lines(..))`.
//! Task 3 scope: line-clipping (`clip::clip_lines`) then depth keys + stable sort
//! (no bsp yet — that lands in T5). The primitives arriving here are already
//! `_prepare-faces` output (meshes exploded, culling applied) on the Typst side,
//! so this module never sees a mesh: it clips lines, then keys each resulting
//! fragment by a single 3-point's camera depth.
use crate::clip::{clip_lines, FragGeom};
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

/// Normalize `-0.0` to `+0.0` for the sort KEY only. Typst's `.sorted` treats
/// `-0.0 == +0.0` (equal, so stable order is preserved), whereas raw `total_cmp`
/// orders `-0.0 < +0.0`. Now that clipping introduces COMPUTED fragment depths
/// (any of which could round to `-0.0`), a comparator must match Typst's
/// equal-treatment or a `-0.0` fragment could sort ahead of a `+0.0` one. The
/// stored `d` (reported back to Typst) is left bit-exact; only the key is
/// normalized. `d` is always finite here (checked below), so `total_cmp` on the
/// normalized key reduces to the ordinary numeric order everywhere else.
fn sort_key(d: f64) -> f64 {
    if d == 0.0 {
        0.0
    } else {
        d
    }
}

/// Clip + depth keys + stable back-to-front sort — mirror of
/// `sort-prims(_clip-lines(prims, camera), camera)` (`render.typ:424-507`).
///
/// First `clip::clip_lines` splits every seg/edge/arrow into its visible
/// fragments (in emission order, non-line prims passing through). Then each
/// fragment gets a depth key: a line fragment keys on its OWN midpoint (the
/// lerp'd endpoints), a label on the literal `1e9`, everything else on its
/// depth point. Non-finite keys are an error. The stable ascending sort mirrors
/// Typst's stable `.sorted(key:)`, preserving emission order for ties (with the
/// `-0.0`/`+0.0` tie-break normalized to match Typst — see `sort_key`).
pub fn run(req: &Request) -> Result<Vec<OutRec>, String> {
    let cam = &req.camera;
    let frags = clip_lines(&req.prims, cam)?;
    let mut keyed: Vec<OutRec> = Vec::with_capacity(frags.len());
    for frag in &frags {
        let i = frag.i;
        let (d, a, b, head) = match &frag.prim {
            FragGeom::PassThrough => {
                let p = &req.prims[i];
                let d = match p {
                    Prim::Label { .. } => 1e9,
                    _ => cam.project(depth_point(p))?.depth,
                };
                (d, None, None, None)
            }
            FragGeom::Line { a, b, head } => {
                // A fragment's depth key is its own midpoint (mirror of
                // `_depth-point` on the lerp'd seg/edge/arrow fragment).
                let d = cam.project(mid(*a, *b))?.depth;
                (d, Some(*a), Some(*b), *head)
            }
        };
        if !d.is_finite() {
            return Err(format!("scenery-engine: non-finite depth for primitive {i}"));
        }
        keyed.push(OutRec { i, d, a, b, head, pts: None });
    }
    keyed.sort_by(|x, y| sort_key(x.d).total_cmp(&sort_key(y.d))); // stable, mirrors Typst .sorted(key:)
    Ok(keyed)
}
