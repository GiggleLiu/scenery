use crate::geom::{cart_to_frac, read3};
use crate::record::{Atom, Meta, Record};

/// Parse a plain `.xyz` or extended-xyz string into a normalized record.
pub fn parse(input: &str) -> Result<Record, String> {
    let mut lines = input.lines();
    let count_line = lines.next().ok_or("empty file")?;
    let n: usize = count_line
        .trim()
        .parse()
        .map_err(|_| format!("first line must be an atom count, got '{}'", count_line.trim()))?;
    let comment = lines.next().unwrap_or("");
    let lattice = parse_lattice(comment)?;

    let mut atoms = Vec::with_capacity(n);
    for (i, line) in lines.by_ref().take(n).enumerate() {
        let mut it = line.split_whitespace();
        let element = it.next().ok_or(format!("atom line {} is empty", i))?.to_string();
        let cart = read3(&mut it, &format!("atom line {}", i))?;
        let frac = match &lattice {
            Some(l) => Some(cart_to_frac(l, cart)?),
            None => None,
        };
        atoms.push(Atom { element, cart, frac });
    }
    if atoms.len() != n {
        return Err(format!("declared {} atoms but found {}", n, atoms.len()));
    }

    let source_format = if lattice.is_some() { "extxyz" } else { "xyz" };
    Ok(Record {
        lattice,
        atoms,
        spacegroup: None,
        asym_unit: None,
        bonds: None,
        meta: Meta { source_format: source_format.into(), n_atoms: n },
    })
}

/// Pull `Lattice="a1 a2 a3 b1 b2 b3 c1 c2 c3"` out of an extended-xyz comment.
fn parse_lattice(comment: &str) -> Result<Option<[[f64; 3]; 3]>, String> {
    let key = "Lattice=\"";
    let start = match comment.find(key) {
        Some(s) => s + key.len(),
        None => return Ok(None),
    };
    let end = comment[start..].find('"').ok_or("unterminated Lattice=\"...\"")? + start;
    let nums: Vec<f64> = comment[start..end]
        .split_whitespace()
        .map(|t| t.parse::<f64>())
        .collect::<Result<_, _>>()
        .map_err(|_| "Lattice contains a non-numeric value".to_string())?;
    if nums.len() != 9 {
        return Err(format!("Lattice needs 9 numbers, got {}", nums.len()));
    }
    Ok(Some([
        [nums[0], nums[1], nums[2]],
        [nums[3], nums[4], nums[5]],
        [nums[6], nums[7], nums[8]],
    ]))
}
