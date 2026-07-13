//! Pinning tests for the line-clipping mirror (S4 Task 3). These transcribe the
//! `_clip-lines` pins from `scenery/tests/test-render.typ:58-197` against the
//! azimuth=elevation=0 camera (coefficients ca=1, sa=0, ce=1, se=0), whose
//! projection maps (x, y, z) -> (sx: x, sy: z, depth: y). The engine's produced
//! fragments must match the pure-Typst `_clip-lines` output bit-identically.
use scenery_engine::clip::{clip_lines, Frag, FragGeom};
use scenery_engine::schema::*;

fn cam0() -> Camera {
    Camera::Ortho { cos_az: 1.0, sin_az: 0.0, cos_el: 1.0, sin_el: 0.0 }
}

/// The `(a, b, head)` of every emitted line fragment, in emission order.
fn lines(frags: &[Frag]) -> Vec<([f64; 3], [f64; 3], Option<bool>)> {
    frags
        .iter()
        .filter_map(|f| match f.prim {
            FragGeom::Line { a, b, head } => Some((a, b, head)),
            FragGeom::PassThrough => None,
        })
        .collect()
}

// 1. Center bond: a seg from the sphere centre outward leaves exactly one visible
//    fragment, beginning at the silhouette (a.x == 1.0).
#[test]
fn center_bond_leaves_one_fragment_at_the_silhouette() {
    let prims = vec![
        Prim::Sphere { c: [0.0, 0.0, 0.0], r: 1.0 },
        Prim::Seg { a: [0.0, 0.0, 0.0], b: [2.0, 0.0, 0.0], w: 0.1 },
    ];
    let frags = clip_lines(&prims, &cam0()).unwrap();
    let ls = lines(&frags);
    assert_eq!(ls.len(), 1, "center bond should leave one visible fragment");
    assert!((ls[0].0[0] - 1.0).abs() < 1e-6, "bond must begin at silhouette, got {:?}", ls[0].0);
}

// 2. A rear edge entirely inside the projected disk is fully hidden.
#[test]
fn rear_edge_inside_disk_is_hidden() {
    let prims = vec![
        Prim::Sphere { c: [0.0, 0.0, 0.0], r: 1.0 },
        Prim::Edge { a: [-0.5, -2.0, 0.0], b: [0.5, -2.0, 0.0] },
    ];
    let frags = clip_lines(&prims, &cam0()).unwrap();
    assert_eq!(lines(&frags).len(), 0, "rear line leaked through sphere");
}

// 3. A line nearer than the sphere's front surface stays visible.
#[test]
fn front_edge_stays_visible() {
    let prims = vec![
        Prim::Sphere { c: [0.0, 0.0, 0.0], r: 1.0 },
        Prim::Edge { a: [-0.5, 2.0, 0.0], b: [0.5, 2.0, 0.0] },
    ];
    let frags = clip_lines(&prims, &cam0()).unwrap();
    assert_eq!(lines(&frags).len(), 1, "foreground line was hidden");
}

// 4. A sloped depth-crossing edge splits into two visible fragments; the
//    later-sorted (by midpoint depth) fragment is in front (d > 0).
#[test]
fn sloped_depth_crossing_splits_in_two() {
    let prims = vec![
        Prim::Sphere { c: [0.0, 0.0, 0.0], r: 1.0 },
        Prim::Edge { a: [0.0, 2.0, 0.0], b: [4.0, -4.0, 0.0] },
    ];
    let frags = clip_lines(&prims, &cam0()).unwrap();
    let ls = lines(&frags);
    assert_eq!(ls.len(), 2, "sphere boundary must split visible depth crossing");
    // Under cam0 a fragment's depth key is its midpoint y.
    let mut depths: Vec<f64> = ls.iter().map(|(a, b, _)| (a[1] + b[1]) / 2.0).collect();
    depths.sort_by(|x, y| x.total_cmp(y));
    assert!(*depths.last().unwrap() > 0.0, "foreground crossing must have d > 0");
}

// 5. Tiny-scale sphere/bond clips at the same relative silhouette.
#[test]
fn tiny_scale_bond_clips_at_scale() {
    let prims = vec![
        Prim::Sphere { c: [0.0, 0.0, 0.0], r: 1e-6 },
        Prim::Seg { a: [0.0, 0.0, 0.0], b: [2e-6, 0.0, 0.0], w: 0.1 },
    ];
    let frags = clip_lines(&prims, &cam0()).unwrap();
    let ls = lines(&frags);
    assert_eq!(ls.len(), 1, "tiny bond should retain its outer half");
    assert!((ls[0].0[0] - 1e-6).abs() < 1e-12, "tiny bond clipped at wrong scale, got {:?}", ls[0].0);
}

// 6. Two disjoint sphere silhouettes split one seg into three fragments.
#[test]
fn two_spheres_split_into_three() {
    let prims = vec![
        Prim::Sphere { c: [-1.0, 0.0, 0.0], r: 0.5 },
        Prim::Sphere { c: [1.0, 0.0, 0.0], r: 0.5 },
        Prim::Seg { a: [-3.0, 0.0, 0.0], b: [3.0, 0.0, 0.0], w: 0.1 },
    ];
    let frags = clip_lines(&prims, &cam0()).unwrap();
    assert_eq!(lines(&frags).len(), 3, "two spheres should split a line into three fragments");
}

// 7. Arrows share the visibility path; only the terminal (t=1) surviving fragment
//    keeps its head. Emission order is ascending interval.
#[test]
fn arrow_through_sphere_keeps_only_terminal_head() {
    let prims = vec![
        Prim::Sphere { c: [0.0, 0.0, 0.0], r: 1.0 },
        Prim::Arrow { a: [-2.0, 0.0, 0.0], b: [2.0, 0.0, 0.0] },
    ];
    let frags = clip_lines(&prims, &cam0()).unwrap();
    let ls = lines(&frags);
    assert_eq!(ls.len(), 2, "sphere must split a crossing arrow");
    assert_eq!(ls[0].2, Some(false), "leading arrow fragment must not draw a head");
    assert_eq!(ls[1].2, Some(true), "terminal arrow fragment must keep its head");
}

#[test]
fn occluded_arrow_tip_drops_its_head() {
    let prims = vec![
        Prim::Sphere { c: [0.0, 0.0, 0.0], r: 1.0 },
        Prim::Arrow { a: [-2.0, 0.0, 0.0], b: [0.0, 0.0, 0.0] },
    ];
    let frags = clip_lines(&prims, &cam0()).unwrap();
    let ls = lines(&frags);
    assert_eq!(ls.len(), 1, "occluded tip leaves one shaft fragment");
    assert_eq!(ls[0].2, Some(false), "an occluded arrow tip must not leave a floating head");
}

#[test]
fn multi_sphere_arrow_has_one_terminal_head() {
    let prims = vec![
        Prim::Sphere { c: [-1.0, 0.0, 0.0], r: 0.5 },
        Prim::Sphere { c: [1.0, 0.0, 0.0], r: 0.5 },
        Prim::Arrow { a: [-3.0, 0.0, 0.0], b: [3.0, 0.0, 0.0] },
    ];
    let frags = clip_lines(&prims, &cam0()).unwrap();
    let ls = lines(&frags);
    assert_eq!(ls.len(), 3, "two spheres split a crossing arrow into three shafts");
    let heads: Vec<bool> = ls.iter().map(|(_, _, h)| h.unwrap()).collect();
    assert_eq!(heads.iter().filter(|&&h| h).count(), 1, "exactly one head survives");
    assert!(*heads.last().unwrap(), "the surviving head is on the terminal fragment");
}

// 8. Broad-phase rejection: a distant sphere must leave an arrow's fragment
//    geometry EXACTLY equal (==) to the no-sphere case.
#[test]
fn distant_sphere_leaves_arrow_geometry_exactly_equal() {
    let arrow = Prim::Arrow { a: [-2.0, 0.0, 0.0], b: [2.0, 0.0, 0.0] };
    let bare = clip_lines(&[arrow.clone()], &cam0()).unwrap();
    let broad = clip_lines(
        &[Prim::Sphere { c: [100.0, 0.0, 100.0], r: 1.0 }, arrow],
        &cam0(),
    )
    .unwrap();
    assert_eq!(lines(&bare), lines(&broad), "broad-phase rejection must preserve an arrow exactly");
}

// 9. An opaque face hides the crossing interval behind its plane. The line
//    (0,-2,0)->(0,2,0) crosses the plane y=1 at t = s0/(s0-s1) = 0.75; only the
//    near half (t in [0.75, 1]) survives, running from the plane to the tip.
#[test]
fn opaque_face_hides_the_rear_crossing_interval() {
    let face = Prim::Face {
        pts: vec![[-1.0, 1.0, -1.0], [1.0, 1.0, -1.0], [1.0, 1.0, 1.0], [-1.0, 1.0, 1.0]],
        opaque: true,
    };
    let prims = vec![face, Prim::Seg { a: [0.0, -2.0, 0.0], b: [0.0, 2.0, 0.0], w: 0.1 }];
    let frags = clip_lines(&prims, &cam0()).unwrap();
    let ls = lines(&frags);
    assert_eq!(ls.len(), 1, "opaque face must remove the rear crossing interval");
    assert!((ls[0].0[1] - 1.0).abs() < 1e-9, "surviving fragment starts at the plane crossing, got {:?}", ls[0].0);
    assert_eq!(ls[0].1, [0.0, 2.0, 0.0], "surviving fragment ends at the line tip");
}

// 10. A translucent face contributes cuts but hides nothing: the same line splits
//     into more fragments whose union is the whole line (total length preserved).
#[test]
fn translucent_face_cuts_but_hides_nothing() {
    let face = Prim::Face {
        pts: vec![[-1.0, 1.0, -1.0], [1.0, 1.0, -1.0], [1.0, 1.0, 1.0], [-1.0, 1.0, 1.0]],
        opaque: false,
    };
    let prims = vec![face, Prim::Seg { a: [0.0, -2.0, 0.0], b: [0.0, 2.0, 0.0], w: 0.1 }];
    let frags = clip_lines(&prims, &cam0()).unwrap();
    let ls = lines(&frags);
    assert_eq!(ls.len(), 2, "translucent face cuts the line without hiding it");
    assert_eq!(ls.first().unwrap().0, [0.0, -2.0, 0.0], "coverage starts at the line origin");
    assert_eq!(ls.last().unwrap().1, [0.0, 2.0, 0.0], "coverage ends at the line tip");
    // Contiguous: each fragment's end is the next fragment's start (full line).
    for w in ls.windows(2) {
        assert_eq!(w[0].1, w[1].0, "translucent split must preserve the complete line");
    }
}
