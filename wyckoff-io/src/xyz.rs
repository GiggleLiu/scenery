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
        let cart = read3(&mut it, i)?;
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

fn read3<'a>(it: &mut impl Iterator<Item = &'a str>, i: usize) -> Result<[f64; 3], String> {
    let mut v = [0.0f64; 3];
    for k in 0..3 {
        let tok = it.next().ok_or(format!("atom line {} needs 3 coordinates", i))?;
        let x: f64 = tok.parse().map_err(|_| format!("bad coordinate '{}' on atom {}", tok, i))?;
        if !x.is_finite() {
            return Err(format!("non-finite coordinate '{}' on atom {}", tok, i));
        }
        v[k] = x;
    }
    Ok(v)
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

/// frac = L^{-1} · cart, where lattice rows are the cell vectors a, b, c.
fn cart_to_frac(l: &[[f64; 3]; 3], c: [f64; 3]) -> Result<[f64; 3], String> {
    // Columns of M are the lattice vectors; solve M · frac = cart.
    let m = [
        [l[0][0], l[1][0], l[2][0]],
        [l[0][1], l[1][1], l[2][1]],
        [l[0][2], l[1][2], l[2][2]],
    ];
    let det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
        - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
        + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
    if det.abs() < 1e-12 {
        return Err("degenerate lattice (zero volume)".into());
    }
    let cof = [
        [ m[1][1]*m[2][2]-m[1][2]*m[2][1], -(m[1][0]*m[2][2]-m[1][2]*m[2][0]),  m[1][0]*m[2][1]-m[1][1]*m[2][0]],
        [-(m[0][1]*m[2][2]-m[0][2]*m[2][1]), m[0][0]*m[2][2]-m[0][2]*m[2][0], -(m[0][0]*m[2][1]-m[0][1]*m[2][0])],
        [ m[0][1]*m[1][2]-m[0][2]*m[1][1], -(m[0][0]*m[1][2]-m[0][2]*m[1][0]),  m[0][0]*m[1][1]-m[0][1]*m[1][0]],
    ];
    // inverse = adjugate / det ; adjugate = cofactor^T, so inverse[i][j] = cof[j][i]/det
    let minv = [
        [cof[0][0]/det, cof[1][0]/det, cof[2][0]/det],
        [cof[0][1]/det, cof[1][1]/det, cof[2][1]/det],
        [cof[0][2]/det, cof[1][2]/det, cof[2][2]/det],
    ];
    Ok([
        minv[0][0]*c[0]+minv[0][1]*c[1]+minv[0][2]*c[2],
        minv[1][0]*c[0]+minv[1][1]*c[1]+minv[1][2]*c[2],
        minv[2][0]*c[0]+minv[2][1]*c[1]+minv[2][2]*c[2],
    ])
}
