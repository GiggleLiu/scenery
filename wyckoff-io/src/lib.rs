#[cfg(target_arch = "wasm32")]
use wasm_minimal_protocol::*;

pub mod record;
pub mod xyz;

#[cfg(target_arch = "wasm32")]
initiate_protocol!();

#[cfg_attr(target_arch = "wasm32", wasm_func)]
pub fn version() -> Vec<u8> {
    format!("wyckoff-io {}", env!("CARGO_PKG_VERSION")).into_bytes()
}

#[cfg_attr(target_arch = "wasm32", wasm_func)]
pub fn echo(input: &[u8]) -> Vec<u8> {
    input.to_vec()
}

#[cfg_attr(target_arch = "wasm32", wasm_func)]
pub fn parse_xyz(input: &[u8]) -> Result<Vec<u8>, String> {
    let text = std::str::from_utf8(input).map_err(|e| e.to_string())?;
    let record = xyz::parse(text)?;
    serde_json::to_vec(&record).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_reports_crate_semver() {
        assert_eq!(version(), b"wyckoff-io 0.1.0".to_vec());
    }

    #[test]
    fn echo_round_trips() {
        assert_eq!(echo(b"hello"), b"hello".to_vec());
    }
}
