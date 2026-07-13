//! The CBOR boundary: request/response types. Host-agnostic — geometry plus the
//! two style-DERIVED geometric facts (face opacity, seg width) only; all colors,
//! gradients, opacity values, and themes stay on the Typst side.
use serde::{Deserialize, Serialize};

#[derive(Deserialize, Debug, Clone, Copy)]
#[serde(tag = "mode", rename_all = "kebab-case")]
pub enum Camera {
    #[serde(rename = "2d")]
    Flat,
    #[serde(rename = "orthographic", rename_all = "kebab-case")]
    Ortho { cos_az: f64, sin_az: f64, cos_el: f64, sin_el: f64 },
    #[serde(rename = "perspective", rename_all = "kebab-case")]
    Persp { cos_az: f64, sin_az: f64, cos_el: f64, sin_el: f64, distance: f64 },
}

#[derive(Deserialize, Debug, Clone, Copy)]
#[serde(rename_all = "kebab-case")]
pub struct Cull {
    pub seg_r_slack: f64,   // wyckoff occlude: sd < depth + seg_r_slack * r   (2.0)
    pub point_r_slack: f64, // covered by sphere: ed < depth + point_r_slack * r (1.0)
    pub seg_w_frac: f64,    // covered by seg stroke: dist2 < (seg_w_frac * w)^2 (0.45)
    pub seg_d_slack: f64,   // ... and ed < seg depth + seg_d_slack             (1.0)
}

#[derive(Deserialize, Debug, Clone)]
#[serde(tag = "k")]
pub enum Prim {
    #[serde(rename = "sphere")] Sphere { c: [f64; 3], r: f64 },
    #[serde(rename = "seg")]    Seg { a: [f64; 3], b: [f64; 3], w: f64 },
    #[serde(rename = "edge")]   Edge { a: [f64; 3], b: [f64; 3] },
    #[serde(rename = "arrow")]  Arrow { a: [f64; 3], b: [f64; 3] },
    #[serde(rename = "face")]   Face { pts: Vec<[f64; 3]>, opaque: bool },
    #[serde(rename = "label")]  Label { p: [f64; 3] },
}

#[derive(Deserialize, Debug)]
pub struct Request {
    pub camera: Camera,
    pub bsp: bool,
    pub cull: Option<Cull>,
    pub prims: Vec<Prim>,
}

/// One draw record; the response is `Vec<OutRec>` in back-to-front draw order.
#[derive(Serialize, Debug, PartialEq)]
pub struct OutRec {
    pub i: usize,
    pub d: f64,
    #[serde(skip_serializing_if = "Option::is_none")] pub a: Option<[f64; 3]>,
    #[serde(skip_serializing_if = "Option::is_none")] pub b: Option<[f64; 3]>,
    #[serde(skip_serializing_if = "Option::is_none")] pub head: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")] pub pts: Option<Vec<[f64; 3]>>,
}
