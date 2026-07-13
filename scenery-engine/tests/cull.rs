//! Coverage-suppression cull tests (S4 Task 7). These pin each slack boundary of
//! the wyckoff `occlude` mirror (`cull::cull_mask`) and the pipeline order
//! (cull FIRST, surviving prims keep their ORIGINAL indices). The camera is the
//! azimuth=elevation=0 orthographic `cam0` (ca=1, sa=0, ce=1, se=0), under which
//! projection is exactly `sx=x, sy=z, depth=y` and `scale_at == 1.0`. Cull
//! constants are wyckoff's verbatim slacks 2.0 / 1.0 / 0.45 / 1.0.
use scenery_engine::cull::cull_mask;
use scenery_engine::pipeline;
use scenery_engine::schema::*;

fn cam0() -> Camera {
    Camera::Ortho { cos_az: 1.0, sin_az: 0.0, cos_el: 1.0, sin_el: 0.0 }
}
fn wy_cull() -> Cull {
    Cull { seg_r_slack: 2.0, point_r_slack: 1.0, seg_w_frac: 0.45, seg_d_slack: 1.0 }
}

// A short seg fully inside a sphere's disk: dropped when not clearly in front
// (sd < depth + 2r), kept once pushed past the slack; the boundary sd == depth+2r
// is KEPT (strict `<`). Sphere (0,0,0) r=1 → disk (0,0) r=1 depth=0, threshold 2.
#[test]
fn seg_inside_disk_drops_behind_keeps_in_front_boundary_kept() {
    // Endpoints screen (0, ±0.2): dist2 = 0.04 < 1, inside the disk.
    let prims = vec![
        Prim::Sphere { c: [0.0, 0.0, 0.0], r: 1.0 },
        // sd = 1 < 2 → dropped
        Prim::Seg { a: [0.0, 1.0, -0.2], b: [0.0, 1.0, 0.2], w: 0.16 },
        // sd = 3, not < 2 → kept
        Prim::Seg { a: [0.0, 3.0, -0.2], b: [0.0, 3.0, 0.2], w: 0.16 },
        // sd = 2 == threshold → kept (strict inequality)
        Prim::Seg { a: [0.0, 2.0, -0.2], b: [0.0, 2.0, 0.2], w: 0.16 },
    ];
    let keep = cull_mask(&prims, &cam0(), &wy_cull()).unwrap();
    assert_eq!(keep, vec![true, false, true, true]);
}

// An edge with both endpoints under a sphere disk and not clearly behind is
// dropped; move one endpoint out of the disk and it survives.
#[test]
fn edge_under_sphere_disk_drops_unless_one_endpoint_free() {
    let sphere = Prim::Sphere { c: [0.0, 0.0, 0.0], r: 1.0 }; // disk (0,0) r1 depth0, thr ed<1
    // Both endpoints inside disk, ed = 0.5 < 1 → both covered → dropped.
    let dropped = vec![
        sphere.clone(),
        Prim::Edge { a: [0.3, 0.5, 0.0], b: [-0.3, 0.5, 0.0] },
    ];
    assert_eq!(cull_mask(&dropped, &cam0(), &wy_cull()).unwrap(), vec![true, false]);
    // One endpoint pushed out of the disk (screen x=5) → that endpoint uncovered.
    let kept = vec![
        sphere,
        Prim::Edge { a: [0.3, 0.5, 0.0], b: [5.0, 0.5, 0.0] },
    ];
    assert_eq!(cull_mask(&kept, &cam0(), &wy_cull()).unwrap(), vec![true, true]);
}

// An edge covered by a wide seg STROKE (dist2 < (0.45 w)^2 and ed < seg depth+1)
// is dropped even with no sphere present.
#[test]
fn edge_covered_by_seg_stroke_is_dropped() {
    // Seg screen (-1,0)->(1,0), depth 0, w=10 → stroke half-width 0.45*10=4.5.
    // Edge endpoints screen (0,0.5),(0.3,0.5): perp dist 0.5, dist2 0.25 < 20.25;
    // ed = 0.5 < 0 + 1.0 → both covered.
    let prims = vec![
        Prim::Seg { a: [-1.0, 0.0, 0.0], b: [1.0, 0.0, 0.0], w: 10.0 },
        Prim::Edge { a: [0.0, 0.5, 0.5], b: [0.3, 0.5, 0.5] },
    ];
    assert_eq!(cull_mask(&prims, &cam0(), &wy_cull()).unwrap(), vec![true, false]);
}

// Spheres, faces and labels always survive, whatever the coverage; a hidden seg
// among them is the only casualty, and survivors keep input order.
#[test]
fn spheres_faces_labels_always_survive_order_preserved() {
    let prims = vec![
        Prim::Sphere { c: [0.0, 0.0, 0.0], r: 1.0 },
        // A face whose centroid sits under the sphere disk — still kept.
        Prim::Face {
            pts: vec![[0.2, 0.5, -0.2], [-0.2, 0.5, -0.2], [0.0, 0.5, 0.2]],
            opaque: false,
        },
        // A label under the disk — kept.
        Prim::Label { p: [0.0, 0.5, 0.0] },
        // A seg fully hidden under the sphere — the only drop.
        Prim::Seg { a: [0.0, 0.5, -0.2], b: [0.0, 0.5, 0.2], w: 0.16 },
    ];
    assert_eq!(cull_mask(&prims, &cam0(), &wy_cull()).unwrap(), vec![true, true, true, false]);
}

// The occluder lists are built BEFORE filtering: a seg that is itself dropped
// (hidden under a sphere) still occludes an edge lying under its stroke.
#[test]
fn dropped_seg_still_occludes_an_edge() {
    // Sphere (0,0,0) r1 hides seg G (screen (0,±0.2), sd 0.5 < 2). G has w=10.
    // Edge E at screen (3,0),(3.1,0): OUT of the sphere disk (dist 3 > 1), so the
    // sphere alone cannot cover it; but within G's stroke (dist2 9,9.61 < 20.25)
    // and ed 0 < G.depth 0.5 + 1 → covered ONLY because the dropped G still counts.
    let prims = vec![
        Prim::Sphere { c: [0.0, 0.0, 0.0], r: 1.0 },
        Prim::Seg { a: [0.0, 0.5, -0.2], b: [0.0, 0.5, 0.2], w: 10.0 },
        Prim::Edge { a: [3.0, 0.0, 0.0], b: [3.1, 0.0, 0.0] },
    ];
    // G dropped (index 1), E dropped (index 2) because G occludes it.
    assert_eq!(cull_mask(&prims, &cam0(), &wy_cull()).unwrap(), vec![true, false, false]);
}

// The pipeline runs cull FIRST and the surviving prims keep their ORIGINAL
// indices in the returned draw records (so Typst reassembles styling correctly).
#[test]
fn pipeline_culls_first_and_preserves_original_indices() {
    let prims = vec![
        Prim::Sphere { c: [0.0, 0.0, 0.0], r: 1.0 },      // 0 kept
        Prim::Seg { a: [0.0, 1.0, -0.2], b: [0.0, 1.0, 0.2], w: 0.16 }, // 1 hidden → dropped
        Prim::Edge { a: [5.0, 0.0, -1.0], b: [5.0, 0.0, 1.0] },         // 2 free → kept
    ];
    let req = Request { camera: cam0(), bsp: true, cull: Some(wy_cull()), prims };
    let out = pipeline::run(&req).unwrap();
    let idx: Vec<usize> = out.iter().map(|r| r.i).collect();
    assert!(!idx.contains(&1), "hidden seg 1 must be culled: {idx:?}");
    assert!(idx.contains(&0) && idx.contains(&2), "survivors keep original indices: {idx:?}");
}
