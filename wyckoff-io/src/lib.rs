#[cfg(target_arch = "wasm32")]
use wasm_minimal_protocol::*;

pub mod bonds;
pub mod cif;
pub mod geom;
pub mod poscar;
pub mod radii;
pub mod record;
pub mod sg_symbols;
pub mod xyz;

use serde::Deserialize;

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

#[cfg_attr(target_arch = "wasm32", wasm_func)]
pub fn parse_poscar(input: &[u8]) -> Result<Vec<u8>, String> {
    let text = std::str::from_utf8(input).map_err(|e| e.to_string())?;
    let record = poscar::parse(text)?;
    serde_json::to_vec(&record).map_err(|e| e.to_string())
}

#[cfg_attr(target_arch = "wasm32", wasm_func)]
pub fn parse_cif(input: &[u8]) -> Result<Vec<u8>, String> {
    let text = std::str::from_utf8(input).map_err(|e| e.to_string())?;
    let record = cif::parse(text)?;
    serde_json::to_vec(&record).map_err(|e| e.to_string())
}

/// One atom of a `detect_bonds` request: `{"element": "Na", "cart": [x,y,z]}`.
#[derive(Deserialize)]
struct BondAtom {
    element: String,
    cart: [f64; 3],
}

/// Render-time bond accelerator: JSON atom list in, JSON `[[i,j], ...]` out.
/// Applies the SAME auto rule as Typst `find-bonds` (see `bonds::find_bonds`),
/// so the Rust path and the Typst path agree exactly on any atom set.
#[cfg_attr(target_arch = "wasm32", wasm_func)]
pub fn detect_bonds(input: &[u8]) -> Result<Vec<u8>, String> {
    let atoms: Vec<BondAtom> = serde_json::from_slice(input).map_err(|e| e.to_string())?;
    let pairs: Vec<(String, [f64; 3])> =
        atoms.into_iter().map(|a| (a.element, a.cart)).collect();
    let bonds = bonds::find_bonds(&pairs);
    serde_json::to_vec(&bonds).map_err(|e| e.to_string())
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
