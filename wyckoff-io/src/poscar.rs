use crate::geom::{cart_to_frac, frac_to_cart, read3};
use crate::record::{Atom, Meta, Record};

/// Parse a VASP 5 POSCAR/CONTCAR into a periodic normalized record.
/// Supported: positive scale, element-symbols line, optional Selective
/// dynamics, Direct or Cartesian coordinates (Cartesian is scaled too).
/// Rejected: negative/zero scale (target-volume form), VASP 4 files without
/// an element-symbols line.
pub fn parse(input: &str) -> Result<Record, String> {
    let mut it = input.lines();
    let _comment = it.next().ok_or("empty POSCAR")?;

    let scale_line = it.next().ok_or("POSCAR truncated: missing scale line")?;
    let scale: f64 = scale_line
        .trim()
        .parse()
        .map_err(|_| format!("POSCAR scale must be a number, got '{}'", scale_line.trim()))?;
    if !(scale.is_finite() && scale > 0.0) {
        return Err(format!(
            "POSCAR scale must be positive, got '{}' (the negative target-volume form is not supported)",
            scale_line.trim()
        ));
    }

    let mut lattice = [[0.0f64; 3]; 3];
    for k in 0..3 {
        let line = it.next().ok_or(format!("POSCAR truncated: missing lattice vector {}", k + 1))?;
        let mut toks = line.split_whitespace();
        lattice[k] = read3(&mut toks, &format!("lattice vector {}", k + 1))?;
        for x in lattice[k].iter_mut() {
            *x *= scale;
        }
    }

    let sym_line = it.next().ok_or("POSCAR truncated: missing element-symbols line")?;
    let symbols: Vec<&str> = sym_line.split_whitespace().collect();
    if symbols.is_empty() {
        return Err("POSCAR element-symbols line is empty".into());
    }
    if symbols[0].parse::<u64>().is_ok() {
        return Err("POSCAR has no element-symbols line (VASP 4 format); insert a VASP 5 \
                    symbols line (e.g. 'Na Cl') before the per-species counts line"
            .into());
    }

    let cnt_line = it.next().ok_or("POSCAR truncated: missing per-species counts line")?;
    let counts: Vec<usize> = cnt_line
        .split_whitespace()
        .map(|t| t.parse::<usize>().map_err(|_| format!("bad species count '{}'", t)))
        .collect::<Result<_, _>>()?;
    if counts.len() != symbols.len() {
        return Err(format!(
            "POSCAR has {} element symbols but {} counts",
            symbols.len(),
            counts.len()
        ));
    }
    let n: usize = counts.iter().sum();

    let mut mode_line = it.next().ok_or("POSCAR truncated: missing coordinate-mode line")?;
    if mode_line.trim_start().starts_with(['S', 's']) {
        // "Selective dynamics" — skip it and read the real mode line.
        mode_line = it
            .next()
            .ok_or("POSCAR truncated: missing coordinate-mode line after Selective dynamics")?;
    }
    let cartesian = match mode_line.trim_start().chars().next() {
        Some('d') | Some('D') => false,
        Some('c') | Some('C') | Some('k') | Some('K') => true,
        _ => {
            return Err(format!(
                "POSCAR coordinate mode must start with D(irect) or C(artesian)/K, got '{}'",
                mode_line.trim()
            ))
        }
    };

    let mut species: Vec<String> = Vec::with_capacity(n);
    for (s, &c) in symbols.iter().zip(&counts) {
        for _ in 0..c {
            species.push((*s).to_string());
        }
    }

    let mut atoms = Vec::with_capacity(n);
    for i in 0..n {
        let line = it
            .next()
            .ok_or(format!("POSCAR declares {} atoms but atom line {} is missing", n, i + 1))?;
        let mut toks = line.split_whitespace();
        let v = read3(&mut toks, &format!("atom line {}", i + 1))?; // trailing T/F flags ignored
        let (cart, frac) = if cartesian {
            let c = [v[0] * scale, v[1] * scale, v[2] * scale];
            let f = cart_to_frac(&lattice, c)?;
            (c, f)
        } else {
            (frac_to_cart(&lattice, v), v)
        };
        atoms.push(Atom { element: species[i].clone(), cart, frac: Some(frac) });
    }

    Ok(Record {
        lattice: Some(lattice),
        atoms,
        spacegroup: None,
        asym_unit: None,
        bonds: None,
        meta: Meta { source_format: "poscar".into(), n_atoms: n },
    })
}
