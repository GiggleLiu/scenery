//! Pinning tests for the depth-sort pipeline (S4 Task 2). These transcribe the
//! documented 4-prim scene from `scenery/tests/test-render.typ:12-49`, whose
//! depth keys are hand-worked there (edge -1, face 1, seg 3, sphere 5 under the
//! azimuth=elevation=0 camera, whose coefficients are exactly ca=1, sa=0, ce=1,
//! se=0). Depth keys must be bit-identical to the Typst path.
use scenery_engine::pipeline;
use scenery_engine::schema::*;

fn cam0() -> Camera {
    Camera::Ortho { cos_az: 1.0, sin_az: 0.0, cos_el: 1.0, sin_el: 0.0 }
}
fn req(camera: Camera, prims: Vec<Prim>) -> Request {
    Request { camera, bsp: true, cull: None, prims }
}

#[test]
fn documented_scene_sorts_back_to_front() {
    // edge y=-1, face centroid y=1, seg y=3, sphere y=5 (test-render.typ:22-27).
    // Under cam0 the depth key is exactly y, independent of x. Task 2's fixture
    // stacked all four at screen x=0; Task 3's now-active clip stage would (rightly)
    // let the near sphere occlude the lines behind it. To keep this a pure
    // depth-sort pin, the prims are separated along screen x so no prim overlaps
    // another's occluder — clipping is a no-op and every prim survives with its
    // unchanged depth key.
    let prims = vec![
        Prim::Edge { a: [10.0, -1.0, -1.0], b: [10.0, -1.0, 1.0] },
        Prim::Face {
            pts: vec![[-1.0, 1.0, -1.0], [1.0, 1.0, -1.0], [0.0, 1.0, 1.0]],
            opaque: true,
        },
        Prim::Seg { a: [20.0, 3.0, -1.0], b: [20.0, 3.0, 1.0], w: 0.12 },
        Prim::Sphere { c: [40.0, 5.0, 0.0], r: 1.0 },
    ];
    let out = pipeline::run(&req(cam0(), prims)).unwrap();
    assert_eq!(out.iter().map(|r| r.i).collect::<Vec<_>>(), vec![0, 1, 2, 3]);
    assert_eq!(out.iter().map(|r| r.d).collect::<Vec<_>>(), vec![-1.0, 1.0, 3.0, 5.0]);
}

#[test]
fn shuffled_input_recovers_the_same_order() {
    // Same prims reversed (screen-x-separated, see above); the back-to-front
    // order recovers indices 3,2,1,0 with clipping a no-op.
    let prims = vec![
        Prim::Sphere { c: [40.0, 5.0, 0.0], r: 1.0 },
        Prim::Seg { a: [20.0, 3.0, -1.0], b: [20.0, 3.0, 1.0], w: 0.12 },
        Prim::Face {
            pts: vec![[-1.0, 1.0, -1.0], [1.0, 1.0, -1.0], [0.0, 1.0, 1.0]],
            opaque: true,
        },
        Prim::Edge { a: [10.0, -1.0, -1.0], b: [10.0, -1.0, 1.0] },
    ];
    let out = pipeline::run(&req(cam0(), prims)).unwrap();
    assert_eq!(out.iter().map(|r| r.i).collect::<Vec<_>>(), vec![3, 2, 1, 0]);
    assert_eq!(out.iter().map(|r| r.d).collect::<Vec<_>>(), vec![-1.0, 1.0, 3.0, 5.0]);
}

#[test]
fn labels_paint_last_with_1e9() {
    // sphere at y=100 vs label: label sorts last with d == 1e9 (render.typ:501)
    let prims = vec![
        Prim::Sphere { c: [0.0, 100.0, 0.0], r: 1.0 },
        Prim::Label { p: [0.0, 0.0, 0.0] },
    ];
    let out = pipeline::run(&req(cam0(), prims)).unwrap();
    assert_eq!(out.iter().map(|r| r.i).collect::<Vec<_>>(), vec![0, 1]);
    assert_eq!(out.last().unwrap().d, 1e9);
    assert_eq!(out.first().unwrap().d, 100.0);
}

#[test]
fn stable_sort_preserves_input_order_on_ties() {
    // Two spheres at identical depth (both y=5): output indices in input order
    // (Typst .sorted is stable; the engine must match).
    let prims = vec![
        Prim::Sphere { c: [0.0, 5.0, 0.0], r: 1.0 },
        Prim::Sphere { c: [3.0, 5.0, 2.0], r: 1.0 },
    ];
    let out = pipeline::run(&req(cam0(), prims)).unwrap();
    assert_eq!(out.iter().map(|r| r.i).collect::<Vec<_>>(), vec![0, 1]);
    assert_eq!(out.iter().map(|r| r.d).collect::<Vec<_>>(), vec![5.0, 5.0]);
}

#[test]
fn perspective_depth_keys_are_unscaled() {
    // Persp{ca:1,sa:0,ce:1,se:0,distance:10}, sphere at y=5: d == 5.0 exactly
    // (Stage-3 pinned convention: the depth key stays the unscaled view depth).
    let cam = Camera::Persp {
        cos_az: 1.0,
        sin_az: 0.0,
        cos_el: 1.0,
        sin_el: 0.0,
        distance: 10.0,
    };
    let prims = vec![Prim::Sphere { c: [0.0, 5.0, 0.0], r: 1.0 }];
    let out = pipeline::run(&req(cam, prims)).unwrap();
    assert_eq!(out[0].d, 5.0);
}

#[test]
fn flat_camera_keeps_input_order() {
    // 2d: every non-label depth is 0.0; output order == input order.
    let prims = vec![
        Prim::Sphere { c: [0.0, 0.0, 0.0], r: 1.0 },
        Prim::Seg { a: [1.0, 1.0, 0.0], b: [2.0, 2.0, 0.0], w: 0.1 },
        Prim::Edge { a: [-1.0, -1.0, 0.0], b: [0.0, 0.0, 0.0] },
    ];
    let out = pipeline::run(&req(Camera::Flat, prims)).unwrap();
    assert_eq!(out.iter().map(|r| r.i).collect::<Vec<_>>(), vec![0, 1, 2]);
    assert_eq!(out.iter().map(|r| r.d).collect::<Vec<_>>(), vec![0.0, 0.0, 0.0]);
}

#[test]
fn behind_perspective_camera_errors() {
    // distance 2, point at y=100: Err containing "at or behind the perspective camera"
    let cam = Camera::Persp {
        cos_az: 1.0,
        sin_az: 0.0,
        cos_el: 1.0,
        sin_el: 0.0,
        distance: 2.0,
    };
    let prims = vec![Prim::Sphere { c: [0.0, 100.0, 0.0], r: 1.0 }];
    let err = pipeline::run(&req(cam, prims)).unwrap_err();
    assert!(
        err.contains("at or behind the perspective camera"),
        "unexpected error message: {err}"
    );
}
