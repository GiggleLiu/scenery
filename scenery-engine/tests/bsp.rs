//! BSP splitting of intersecting translucent faces (S4 Task 5, issue #33).
//!
//! The canonical analytic scene: two unit-ish rectangles crossing along the
//! x-axis. Q1 lies in the z=0 plane (normal ±z); Q2 in the y=0 plane (normal
//! ±y). They interpenetrate along the segment x∈[-1.5,1.5], y=z=0. Under a
//! painter's centroid sort ONE quad is drawn entirely over the other — wrong on
//! one side of the crossing. BSP splits each quad by the other's plane so the
//! four half-quads sort into the correct back-to-front interleaving.
use scenery_engine::bsp::{self, FaceFrag};
use scenery_engine::pipeline;
use scenery_engine::schema::*;

fn q1() -> Prim {
    Prim::Face {
        pts: vec![[-1.5, -1.0, 0.0], [1.5, -1.0, 0.0], [1.5, 1.0, 0.0], [-1.5, 1.0, 0.0]],
        opaque: false,
    }
}
fn q2() -> Prim {
    Prim::Face {
        pts: vec![[-1.5, 0.0, -1.0], [1.5, 0.0, -1.0], [1.5, 0.0, 1.0], [-1.5, 0.0, 1.0]],
        opaque: false,
    }
}

// Elevation 30° camera: depth direction (0, cos30, sin30); cos30 = √3/2.
fn cam30() -> Camera {
    Camera::Ortho { cos_az: 1.0, sin_az: 0.0, cos_el: 3f64.sqrt() / 2.0, sin_el: 0.5 }
}

fn req(camera: Camera, bsp: bool, prims: Vec<Prim>) -> Request {
    Request { camera, bsp, cull: None, prims, depth_keys: vec![] }
}

fn pts_of(p: &Prim) -> &[[f64; 3]] {
    match p {
        Prim::Face { pts, .. } => pts,
        _ => panic!("not a face"),
    }
}

// Unit-normal plane (n, o) of a polygon; signed distance of q is n·(q-o).
fn plane(pts: &[[f64; 3]]) -> ([f64; 3], [f64; 3]) {
    let o = pts[0];
    // Newell-ish: first non-degenerate edge-pair cross, then normalize.
    let sub = |a: [f64; 3], b: [f64; 3]| [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
    let cross = |a: [f64; 3], b: [f64; 3]| {
        [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
    };
    let mut n = [0.0, 0.0, 0.0];
    for i in 1..pts.len() - 1 {
        let c = cross(sub(pts[i], o), sub(pts[i + 1], o));
        let l = (c[0] * c[0] + c[1] * c[1] + c[2] * c[2]).sqrt();
        if l > 1e-12 {
            n = [c[0] / l, c[1] / l, c[2] / l];
            break;
        }
    }
    (n, o)
}
fn signed(n: [f64; 3], o: [f64; 3], q: [f64; 3]) -> f64 {
    n[0] * (q[0] - o[0]) + n[1] * (q[1] - o[1]) + n[2] * (q[2] - o[2])
}

// #1 Split count: two crossing translucent quads -> exactly 4 face records,
//    all carrying pts (split: true), two per input index.
#[test]
fn two_crossing_quads_split_into_four_fragments() {
    let out = pipeline::run(&req(cam30(), true, vec![q1(), q2()])).unwrap();
    assert_eq!(out.len(), 4, "two crossing quads split into four fragments");
    assert!(out.iter().all(|r| r.pts.is_some()), "every fragment carries split geometry");
    assert!(out.iter().all(|r| r.pts.as_ref().unwrap().len() >= 3), "each piece is a polygon");
    let i0 = out.iter().filter(|r| r.i == 0).count();
    let i1 = out.iter().filter(|r| r.i == 1).count();
    assert_eq!((i0, i1), (2, 2), "each input index yields two pieces");
}

// #2 Plane-side invariant: every fragment lies entirely on ONE side (within eps)
//    of the OTHER original face's plane.
#[test]
fn each_fragment_lies_on_one_side_of_partner_plane() {
    let prims = vec![q1(), q2()];
    let out = pipeline::run(&req(cam30(), true, prims.clone())).unwrap();
    let planes = [plane(pts_of(&prims[0])), plane(pts_of(&prims[1]))];
    let eps = 1e-9;
    for r in &out {
        let partner = planes[1 - r.i]; // the OTHER face's plane
        let pts = r.pts.as_ref().unwrap();
        let ds: Vec<f64> = pts.iter().map(|q| signed(partner.0, partner.1, *q)).collect();
        let has_pos = ds.iter().any(|&d| d > eps);
        let has_neg = ds.iter().any(|&d| d < -eps);
        assert!(
            !(has_pos && has_neg),
            "fragment of face {} straddles partner plane: {:?}",
            r.i,
            ds
        );
    }
}

// #3 Hand-pinned depth keys. Q1 halves have centroids (0, ∓0.5, 0); Q2 halves
//    (0, 0, ∓0.5). Under the 30° camera depth = y·cos30 + z·sin30, so the sorted
//    keys are Q1-back, Q2-bottom, Q2-top, Q1-front.
#[test]
fn hand_pinned_depth_keys_interleave_correctly() {
    let out = pipeline::run(&req(cam30(), true, vec![q1(), q2()])).unwrap();
    let cos30 = 3f64.sqrt() / 2.0;
    let expected = [-0.5 * cos30, -0.25, 0.25, 0.5 * cos30];
    let got: Vec<f64> = out.iter().map(|r| r.d).collect();
    for (g, e) in got.iter().zip(expected.iter()) {
        assert!((g - e).abs() < 1e-12, "depth key {g} != expected {e}");
    }
    // Painter correctness: each later-drawn fragment is on the viewer side of
    // every earlier overlapping fragment's plane. The interleave (Q1,Q2,Q2,Q1)
    // is exactly what a single centroid sort cannot produce for whole quads.
    assert_eq!(out.iter().map(|r| r.i).collect::<Vec<_>>(), vec![0, 1, 1, 0]);
}

// #4a Negative control: DISJOINT translucent faces -> no split. Output carries
//     pts: None and equals the no-BSP pipeline output exactly.
#[test]
fn disjoint_faces_produce_no_spurious_splits() {
    let q2_apart = Prim::Face {
        pts: vec![[-1.5, 2.5, -1.0], [1.5, 2.5, -1.0], [1.5, 2.5, 1.0], [-1.5, 2.5, 1.0]],
        opaque: false,
    };
    let with_bsp = pipeline::run(&req(cam30(), true, vec![q1(), q2_apart.clone()])).unwrap();
    let no_bsp = pipeline::run(&req(cam30(), false, vec![q1(), q2_apart])).unwrap();
    assert!(with_bsp.iter().all(|r| r.pts.is_none()), "no fragment is split");
    assert_eq!(with_bsp, no_bsp, "BSP output identical to the plain painter's sort");
}

// #4b Negative control: two PARALLEL (coplanar-offset) translucent faces.
#[test]
fn parallel_faces_produce_no_splits() {
    let top = Prim::Face {
        pts: vec![[-1.5, -1.0, 0.5], [1.5, -1.0, 0.5], [1.5, 1.0, 0.5], [-1.5, 1.0, 0.5]],
        opaque: false,
    };
    let with_bsp = pipeline::run(&req(cam30(), true, vec![q1(), top.clone()])).unwrap();
    let no_bsp = pipeline::run(&req(cam30(), false, vec![q1(), top])).unwrap();
    assert!(with_bsp.iter().all(|r| r.pts.is_none()));
    assert_eq!(with_bsp, no_bsp);
}

// #4c Negative control: a translucent face crossed by an OPAQUE face. BSP is
//     translucent-only, so nothing splits.
#[test]
fn opaque_partner_produces_no_splits() {
    let opaque_q2 = Prim::Face {
        pts: vec![[-1.5, 0.0, -1.0], [1.5, 0.0, -1.0], [1.5, 0.0, 1.0], [-1.5, 0.0, 1.0]],
        opaque: true,
    };
    let with_bsp = pipeline::run(&req(cam30(), true, vec![q1(), opaque_q2.clone()])).unwrap();
    let no_bsp = pipeline::run(&req(cam30(), false, vec![q1(), opaque_q2])).unwrap();
    assert!(with_bsp.iter().all(|r| r.pts.is_none()), "translucent face is not split");
    assert_eq!(with_bsp, no_bsp);
}

// #4d Negative control (chord test has teeth): face B's PLANE is crossed by face
//     A, but A's polygon is offset far along x so the chord misses it entirely.
#[test]
fn plane_crossing_without_polygon_overlap_produces_no_splits() {
    // A: z=0 plane at x∈[10,12]; B: y=0 plane at x∈[-1.5,1.5]. Each plane is
    // crossed by the other, but their polygons never overlap.
    let a = Prim::Face {
        pts: vec![[10.0, -1.0, 0.0], [12.0, -1.0, 0.0], [12.0, 1.0, 0.0], [10.0, 1.0, 0.0]],
        opaque: false,
    };
    let b = Prim::Face {
        pts: vec![[-1.5, 0.0, -1.0], [1.5, 0.0, -1.0], [1.5, 0.0, 1.0], [-1.5, 0.0, 1.0]],
        opaque: false,
    };
    let with_bsp = pipeline::run(&req(cam30(), true, vec![a.clone(), b.clone()])).unwrap();
    let no_bsp = pipeline::run(&req(cam30(), false, vec![a, b])).unwrap();
    assert!(with_bsp.iter().all(|r| r.pts.is_none()), "chord misses polygon -> no split");
    assert_eq!(with_bsp, no_bsp);
}

// #5 Three-face chain: Q1 (z=0), Q2 (y=0), Q3 (x=0.2, crossing both). Every
//    output fragment lies on one side of BOTH its partners' planes, and the
//    result is bit-identical across two runs (determinism).
#[test]
fn three_face_chain_invariant_and_deterministic() {
    let q3 = Prim::Face {
        pts: vec![[0.2, -1.5, -1.5], [0.2, 1.5, -1.5], [0.2, 1.5, 1.5], [0.2, -1.5, 1.5]],
        opaque: false,
    };
    let prims = vec![q1(), q2(), q3];
    let run1 = pipeline::run(&req(cam30(), true, prims.clone())).unwrap();
    let run2 = pipeline::run(&req(cam30(), true, prims.clone())).unwrap();
    assert_eq!(run1, run2, "BSP output is deterministic across runs");

    let planes = [
        plane(pts_of(&prims[0])),
        plane(pts_of(&prims[1])),
        plane(pts_of(&prims[2])),
    ];
    let eps = 1e-9;
    for r in &run1 {
        let pts: &[[f64; 3]] = r.pts.as_deref().unwrap_or_else(|| pts_of(&prims[r.i]));
        for (j, pl) in planes.iter().enumerate() {
            if j == r.i {
                continue;
            }
            let ds: Vec<f64> = pts.iter().map(|q| signed(pl.0, pl.1, *q)).collect();
            let has_pos = ds.iter().any(|&d| d > eps);
            let has_neg = ds.iter().any(|&d| d < -eps);
            assert!(
                !(has_pos && has_neg),
                "fragment of face {} straddles plane of face {j}: {:?}",
                r.i,
                ds
            );
        }
    }
}

// Direct unit test of `split_translucent`: components of size 1 pass through
// untouched (split: false); the returned frags preserve every input index.
#[test]
fn split_translucent_passes_isolated_faces_through() {
    let far = FaceFrag {
        i: 7,
        pts: vec![[100.0, -1.0, 0.0], [102.0, -1.0, 0.0], [102.0, 1.0, 0.0], [100.0, 1.0, 0.0]],
        split: false,
    };
    let out = bsp::split_translucent(vec![far]);
    assert_eq!(out.len(), 1);
    assert!(!out[0].split, "isolated face untouched");
    assert_eq!(out[0].i, 7);
}

// bsp:false must reproduce the plain painter's sort even on the crossing scene:
// two whole quads, no split geometry.
#[test]
fn bsp_false_leaves_crossing_quads_unsplit() {
    let out = pipeline::run(&req(cam30(), false, vec![q1(), q2()])).unwrap();
    assert_eq!(out.len(), 2, "no splitting when bsp is off");
    assert!(out.iter().all(|r| r.pts.is_none()));
}
