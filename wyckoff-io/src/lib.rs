use wasm_minimal_protocol::*;

initiate_protocol!();

#[wasm_func]
pub fn version() -> Vec<u8> {
    format!("wyckoff-io {}", env!("CARGO_PKG_VERSION")).into_bytes()
}

#[wasm_func]
pub fn echo(input: &[u8]) -> Vec<u8> {
    input.to_vec()
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
