#[cfg(target_arch = "wasm32")]
use wasm_minimal_protocol::*;

pub mod camera;
pub mod clip;
pub mod pipeline;
pub mod schema;

#[cfg(target_arch = "wasm32")]
initiate_protocol!();

#[cfg_attr(target_arch = "wasm32", wasm_func)]
pub fn version() -> Vec<u8> {
    format!("scenery-engine {}", env!("CARGO_PKG_VERSION")).into_bytes()
}

#[cfg_attr(target_arch = "wasm32", wasm_func)]
pub fn echo(input: &[u8]) -> Vec<u8> {
    input.to_vec()
}

/// Primitives + camera in (CBOR), depth-ordered primitives with depth keys out
/// (CBOR). Task 2: depth keys + stable back-to-front sort (mirror of render.typ
/// `sort-prims`); Tasks 3-5 add cull -> clip -> bsp splitting.
#[cfg_attr(target_arch = "wasm32", wasm_func)]
pub fn sort_scene(input: &[u8]) -> Result<Vec<u8>, String> {
    let req: schema::Request =
        ciborium::from_reader(input).map_err(|e| format!("scenery-engine: bad request: {e}"))?;
    let out = pipeline::run(&req)?;
    let mut buf = Vec::new();
    ciborium::into_writer(&out, &mut buf)
        .map_err(|e| format!("scenery-engine: encode failed: {e}"))?;
    Ok(buf)
}

#[cfg(test)]
mod tests {
    use super::*;
    use ciborium::value::Value;

    #[test]
    fn version_reports_crate_semver() {
        assert_eq!(version(), b"scenery-engine 0.1.0".to_vec());
    }

    #[test]
    fn sort_scene_round_trips_the_schema() {
        // A hand-encoded request exercising every prim kind and camera field.
        let req = serde_json_like_cbor(); // helper below builds CBOR bytes via ciborium::Value
        let out = sort_scene(&req).expect("stub must decode the full schema");
        let recs: Vec<ciborium::Value> = ciborium::from_reader(&out[..]).unwrap();
        // With clipping active (Task 3) the translucent face splits the arrow at
        // its projected edge, so the six input prims yield seven records; every
        // source index 0..=5 is still represented.
        assert_eq!(recs.len(), 7);
        let indices: Vec<i128> = recs
            .iter()
            .map(|r| match r {
                ciborium::Value::Map(m) => m
                    .iter()
                    .find(|(k, _)| matches!(k, ciborium::Value::Text(t) if t == "i"))
                    .and_then(|(_, v)| match v {
                        ciborium::Value::Integer(n) => Some((*n).into()),
                        _ => None,
                    })
                    .expect("record has an integer `i`"),
                _ => panic!("record must be a map"),
            })
            .collect();
        for i in 0..=5i128 {
            assert!(indices.contains(&i), "source prim {i} must appear in the output");
        }
    }

    #[test]
    fn echo_is_identity() {
        assert_eq!(echo(b"hello scenery"), b"hello scenery".to_vec());
    }

    #[test]
    fn sort_scene_rejects_garbage() {
        // Not valid CBOR for a Request -> Err, not panic.
        assert!(sort_scene(&[0xff, 0x00, 0x13, 0x37]).is_err());
    }

    // Small builders keeping the ciborium::Value literals readable.
    fn s(text: &str) -> Value {
        Value::Text(text.to_string())
    }
    fn f(x: f64) -> Value {
        Value::Float(x)
    }
    fn pt(x: f64, y: f64, z: f64) -> Value {
        Value::Array(vec![f(x), f(y), f(z)])
    }
    fn map(pairs: Vec<(&str, Value)>) -> Value {
        Value::Map(pairs.into_iter().map(|(k, v)| (s(k), v)).collect())
    }

    // Build the request with ciborium::Value maps mirroring the documented schema
    // (all six prim kinds, orthographic camera with the four coefficients,
    // bsp: true, cull: null).
    fn serde_json_like_cbor() -> Vec<u8> {
        let camera = map(vec![
            ("mode", s("orthographic")),
            ("cos-az", f(0.9063077870366499)),
            ("sin-az", f(0.4226182617406994)),
            ("cos-el", f(0.9659258262890683)),
            ("sin-el", f(0.25881904510252074)),
        ]);
        let prims = Value::Array(vec![
            map(vec![("k", s("sphere")), ("c", pt(0.0, 5.0, 0.0)), ("r", f(1.0))]),
            map(vec![
                ("k", s("seg")),
                ("a", pt(0.0, 3.0, -1.0)),
                ("b", pt(0.0, 3.0, 1.0)),
                ("w", f(0.12)),
            ]),
            map(vec![
                ("k", s("edge")),
                ("a", pt(0.0, -1.0, -1.0)),
                ("b", pt(0.0, -1.0, 1.0)),
            ]),
            map(vec![
                ("k", s("arrow")),
                ("a", pt(0.0, 2.0, 0.0)),
                ("b", pt(1.0, 2.0, 0.0)),
            ]),
            map(vec![
                ("k", s("face")),
                (
                    "pts",
                    Value::Array(vec![
                        pt(-1.0, 1.0, -1.0),
                        pt(1.0, 1.0, -1.0),
                        pt(0.0, 1.0, 1.0),
                    ]),
                ),
                ("opaque", Value::Bool(false)),
            ]),
            map(vec![("k", s("label")), ("p", pt(0.0, 0.0, 0.0))]),
        ]);
        let req = map(vec![
            ("camera", camera),
            ("bsp", Value::Bool(true)),
            ("cull", Value::Null),
            ("prims", prims),
        ]);
        let mut buf = Vec::new();
        ciborium::into_writer(&req, &mut buf).expect("encode request");
        buf
    }
}
