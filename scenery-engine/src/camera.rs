//! Projection — the exact mirror of `scenery/src/camera.typ`. The camera crosses
//! the CBOR boundary as PRECOMPUTED cos/sin coefficients (see `schema::Camera`),
//! so this module performs only exactly-rounded arithmetic (`+ - * / sqrt`) on
//! those coefficients. It never calls libm trig: that would be platform- and
//! version-dependent and would break bit-identical depth keys against Typst.
use crate::schema::Camera;

/// Screen coordinates plus a depth value, mirroring the dictionary returned by
/// `camera.typ` `project` (`(sx, sy, depth)`).
pub struct Proj {
    pub sx: f64,
    pub sy: f64,
    pub depth: f64,
}

impl Camera {
    /// Mirror of `camera.typ:50-58` `project-scale`: `1.0` for orthographic/2d
    /// cameras; `distance / (distance - depth)` for perspective, `Err` when
    /// `!(denom > 1e-9 * distance)` (mirrors the Typst assert; message contains
    /// "at or behind the perspective camera").
    pub fn scale_at(&self, depth: f64) -> Result<f64, String> {
        match self {
            Camera::Persp { distance, .. } => {
                let distance = *distance;
                let denom = distance - depth;
                if !(denom > 1e-9 * distance) {
                    return Err(format!(
                        "scenery: point at camera depth {depth} is at or behind the \
                         perspective camera (distance: {distance}); increase the \
                         camera's distance"
                    ));
                }
                Ok(distance / denom)
            }
            _ => Ok(1.0),
        }
    }

    /// Mirror of `camera.typ:76-92` `project`, with the trig replaced by the
    /// shipped coefficients and the SAME expression association order:
    ///   x1 = x*ca + y*sa;  y1 = -x*sa + y*ca;
    ///   sy = -y1*se + z*ce;  depth = y1*ce + z*se;
    /// Perspective: `s = scale_at(depth)`; `sx = x1*s`, `sy = sy*s`; `depth`
    /// stays UNSCALED (so depth sorting is identical across the two 3D modes).
    /// 2d: `(sx: x, sy: y, depth: 0.0)`.
    pub fn project(&self, p: [f64; 3]) -> Result<Proj, String> {
        let [x, y, z] = p;
        match self {
            Camera::Flat => Ok(Proj { sx: x, sy: y, depth: 0.0 }),
            Camera::Ortho { cos_az, sin_az, cos_el, sin_el } => {
                let (ca, sa, ce, se) = (*cos_az, *sin_az, *cos_el, *sin_el);
                let x1 = x * ca + y * sa;
                let y1 = -x * sa + y * ca;
                let sy = -y1 * se + z * ce;
                let depth = y1 * ce + z * se;
                Ok(Proj { sx: x1, sy, depth })
            }
            Camera::Persp { cos_az, sin_az, cos_el, sin_el, .. } => {
                let (ca, sa, ce, se) = (*cos_az, *sin_az, *cos_el, *sin_el);
                let x1 = x * ca + y * sa;
                let y1 = -x * sa + y * ca;
                let sy = -y1 * se + z * ce;
                let depth = y1 * ce + z * se;
                let s = self.scale_at(depth)?;
                Ok(Proj { sx: x1 * s, sy: sy * s, depth })
            }
        }
    }
}
