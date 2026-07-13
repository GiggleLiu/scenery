//! Pragmatic CIF subset parser. Supported: a single data_ block, cell
//! parameters, one atom-site loop, and symmetry via an explicit op loop
//! (applied here) or a spacegroup identifier (returned for Typst table
//! expansion). Rejected with precise errors: multiple data blocks, partial
//! occupancy, malformed loops, and files with neither ops nor identifier.

use crate::geom::{cell_to_vectors, frac_to_cart, wrap01};
use crate::record::{AsymAtom, Atom, Meta, Record};
use crate::sg_symbols::SG_SYMBOLS;
use std::collections::HashMap;

/// Fractional-coordinate tolerance when deduplicating op images (periodic
/// min-image). File coordinates are low-precision; distinct atoms are far apart.
const DEDUP_EPS: f64 = 1e-3;

pub struct SymOp {
    pub rot: [[i32; 3]; 3],
    pub trans: [f64; 3],
}

/// Parse one symmetry-op string like "-y+1/2, x-y, z" into rot + trans.
/// Grammar: see the Stage 2 plan (Task 4). Whitespace ignored, case-insensitive.
pub fn parse_op(s: &str) -> Result<SymOp, String> {
    let comps: Vec<&str> = s.split(',').collect();
    if comps.len() != 3 {
        return Err(format!("symmetry op '{}' must have 3 comma-separated components", s));
    }
    let mut rot = [[0i32; 3]; 3];
    let mut trans = [0.0f64; 3];
    for (i, comp) in comps.iter().enumerate() {
        let chars: Vec<char> = comp.chars().filter(|c| !c.is_whitespace()).collect();
        if chars.is_empty() {
            return Err(format!("symmetry op '{}': component {} is empty", s, i + 1));
        }
        let mut k = 0;
        while k < chars.len() {
            let mut sign = 1i32;
            while k < chars.len() && (chars[k] == '+' || chars[k] == '-') {
                if chars[k] == '-' {
                    sign = -sign;
                }
                k += 1;
            }
            if k >= chars.len() {
                return Err(format!("symmetry op '{}': dangling sign in component {}", s, i + 1));
            }
            let c = chars[k].to_ascii_lowercase();
            if c == 'x' || c == 'y' || c == 'z' {
                rot[i][(c as u8 - b'x') as usize] += sign;
                k += 1;
            } else if c.is_ascii_digit() || c == '.' {
                let start = k;
                while k < chars.len() && (chars[k].is_ascii_digit() || chars[k] == '.') {
                    k += 1;
                }
                let numtok: String = chars[start..k].iter().collect();
                let val = if k < chars.len() && chars[k] == '/' {
                    k += 1;
                    let dstart = k;
                    while k < chars.len() && chars[k].is_ascii_digit() {
                        k += 1;
                    }
                    let dentok: String = chars[dstart..k].iter().collect();
                    let n: f64 = numtok.parse().map_err(|_| format!("symmetry op '{}': bad numerator '{}'", s, numtok))?;
                    let d: f64 = dentok.parse().map_err(|_| format!("symmetry op '{}': bad denominator '{}'", s, dentok))?;
                    if d == 0.0 {
                        return Err(format!("symmetry op '{}': division by zero", s));
                    }
                    n / d
                } else {
                    numtok.parse().map_err(|_| format!("symmetry op '{}': bad number '{}'", s, numtok))?
                };
                trans[i] += sign as f64 * val;
            } else {
                return Err(format!("symmetry op '{}': unexpected character '{}'", s, chars[k]));
            }
        }
        trans[i] = wrap01(trans[i]);
    }
    Ok(SymOp { rot, trans })
}

/// q = R·f + t, each component wrapped into [0, 1).
pub fn apply_op(op: &SymOp, f: [f64; 3]) -> [f64; 3] {
    [0, 1, 2].map(|i| {
        wrap01(op.rot[i][0] as f64 * f[0] + op.rot[i][1] as f64 * f[1] + op.rot[i][2] as f64 * f[2] + op.trans[i])
    })
}

/// Derive an element symbol from a CIF type_symbol or label token:
/// "Na1" -> "Na", "O2-" -> "O", "NA" -> "Na", "Ca2+" -> "Ca".
pub fn element_symbol(token: &str) -> Result<String, String> {
    let alpha: String = token.chars().take_while(|c| c.is_ascii_alphabetic()).collect();
    if alpha.is_empty() || alpha.len() > 2 {
        return Err(format!("cannot derive an element symbol from '{}'", token));
    }
    Ok(alpha
        .chars()
        .enumerate()
        .map(|(i, ch)| if i == 0 { ch.to_ascii_uppercase() } else { ch.to_ascii_lowercase() })
        .collect())
}

fn frac_close(p: [f64; 3], q: [f64; 3]) -> bool {
    p.iter().zip(&q).all(|(a, b)| {
        let d = (a - b).abs();
        d.min((d - 1.0).abs()) < DEDUP_EPS
    })
}

struct Loop {
    tags: Vec<String>,          // lowercased, in column order
    rows: Vec<Vec<String>>,     // each row has tags.len() values (quotes stripped)
}

struct Cif {
    scalars: HashMap<String, String>, // lowercased tag -> value (quotes stripped)
    loops: Vec<Loop>,
}

fn find_loop<'a>(cif: &'a Cif, tag: &str) -> Option<(&'a Loop, usize)> {
    cif.loops.iter().find_map(|lp| lp.tags.iter().position(|t| t == tag).map(|i| (lp, i)))
}

/// Strip a trailing "(su)" uncertainty suffix and parse; "." / "?" are errors.
fn num(v: &str) -> Result<f64, String> {
    let base = match v.find('(') {
        Some(i) => &v[..i],
        None => v,
    };
    if base == "." || base == "?" || base.is_empty() {
        return Err(format!("CIF value '{}' is unknown/absent where a number is required", v));
    }
    base.parse().map_err(|_| format!("CIF value '{}' is not a number", v))
}

/// One lexer token plus whether it came from a quoted string (a quoted token is
/// never interpreted as a keyword or tag, so op strings with commas survive).
struct Token {
    text: String,
    quoted: bool,
}

impl Token {
    /// Is this an unquoted structural token: a tag (`_...`), `loop_`, or a
    /// `data_` header? Such a token ends a preceding loop's value run.
    fn is_control(&self) -> bool {
        if self.quoted {
            return false;
        }
        let lower = self.text.to_ascii_lowercase();
        self.text.starts_with('_') || lower == "loop_" || lower.starts_with("data_")
    }
}

/// Tokenize per the Stage 2 plan spec: semicolon text blocks skipped, quoted
/// tokens ('...'/"...") kept whole with quotes stripped, '#' comments ended at
/// end of line, loop_ / data_ keywords case-insensitive, tags lowercased,
/// loop value count must be an exact multiple of the column count
/// (else Err containing "malformed loop" and the first column tag),
/// >1 data_ block is an error.
fn tokenize(input: &str) -> Result<Cif, String> {
    // --- Phase 1: line-oriented lexing into a flat token stream. ---
    let mut tokens: Vec<Token> = Vec::new();
    let mut lines = input.lines();
    while let Some(line) = lines.next() {
        // A line whose first character is ';' opens a multi-line text field;
        // skip everything up to and including the next line starting with ';'.
        if line.starts_with(';') {
            for l in lines.by_ref() {
                if l.starts_with(';') {
                    break;
                }
            }
            continue;
        }
        let chars: Vec<char> = line.chars().collect();
        let mut i = 0;
        while i < chars.len() {
            let c = chars[i];
            if c.is_whitespace() {
                i += 1;
                continue;
            }
            // An unquoted token starting with '#' ends the line (comment).
            if c == '#' {
                break;
            }
            if c == '\'' || c == '"' {
                let quote = c;
                i += 1;
                let start = i;
                while i < chars.len() && chars[i] != quote {
                    i += 1;
                }
                if i >= chars.len() {
                    return Err(format!("CIF has an unterminated quoted string on line: {}", line));
                }
                let text: String = chars[start..i].iter().collect();
                i += 1; // consume closing quote
                tokens.push(Token { text, quoted: true });
            } else {
                let start = i;
                while i < chars.len() && !chars[i].is_whitespace() {
                    i += 1;
                }
                let text: String = chars[start..i].iter().collect();
                tokens.push(Token { text, quoted: false });
            }
        }
    }

    // --- Phase 2: stream grammar -> scalars + loops. ---
    let mut scalars: HashMap<String, String> = HashMap::new();
    let mut loops: Vec<Loop> = Vec::new();
    let mut data_blocks = 0usize;
    let mut i = 0;
    while i < tokens.len() {
        let t = &tokens[i];
        if !t.quoted {
            let lower = t.text.to_ascii_lowercase();
            if lower == "loop_" {
                i += 1;
                // Column tags: consecutive `_tag` tokens.
                let mut tags: Vec<String> = Vec::new();
                while i < tokens.len() && !tokens[i].quoted && tokens[i].text.starts_with('_') {
                    tags.push(tokens[i].text.to_ascii_lowercase());
                    i += 1;
                }
                if tags.is_empty() {
                    return Err("CIF loop_ has no column tags".into());
                }
                // Values until the next control token or EOF.
                let mut values: Vec<String> = Vec::new();
                while i < tokens.len() && !tokens[i].is_control() {
                    values.push(tokens[i].text.clone());
                    i += 1;
                }
                let ncol = tags.len();
                if values.len() % ncol != 0 {
                    return Err(format!(
                        "malformed loop starting at {}: {} values is not a multiple of {} columns",
                        tags[0],
                        values.len(),
                        ncol
                    ));
                }
                let rows = values.chunks(ncol).map(|c| c.to_vec()).collect();
                loops.push(Loop { tags, rows });
                continue;
            }
            if lower.starts_with("data_") {
                data_blocks += 1;
                if data_blocks > 1 {
                    return Err("CIF has multiple data_ blocks; only single-block files are supported".into());
                }
                i += 1;
                continue;
            }
            if t.text.starts_with('_') {
                // Bare tag outside a loop: the single next token is its value.
                let tag = t.text.to_ascii_lowercase();
                i += 1;
                if i >= tokens.len() || tokens[i].is_control() {
                    return Err(format!("CIF tag {} has no value", tag));
                }
                scalars.insert(tag, tokens[i].text.clone());
                i += 1;
                continue;
            }
        }
        // A stray value token outside any loop/tag context: ignore it.
        i += 1;
    }

    Ok(Cif { scalars, loops })
}

pub fn parse(input: &str) -> Result<Record, String> {
    let cif = tokenize(input)?;

    // 1. Cell parameters -> lattice vectors.
    let mut cell = [0.0f64; 6];
    for (k, tag) in ["_cell_length_a", "_cell_length_b", "_cell_length_c",
                     "_cell_angle_alpha", "_cell_angle_beta", "_cell_angle_gamma"]
        .iter()
        .enumerate()
    {
        let v = cif.scalars.get(*tag).ok_or_else(|| format!("CIF is missing required tag {}", tag))?;
        cell[k] = num(v)?;
    }
    let lattice = cell_to_vectors(cell[0], cell[1], cell[2], cell[3], cell[4], cell[5])?;

    // 2. Asymmetric unit from the atom-site loop.
    let (site_loop, xcol) = find_loop(&cif, "_atom_site_fract_x")
        .ok_or("CIF has no atom-site loop (_atom_site_fract_x/_y/_z)")?;
    let col = |tag: &str| site_loop.tags.iter().position(|t| t == tag);
    let ycol = col("_atom_site_fract_y").ok_or("atom-site loop is missing _atom_site_fract_y")?;
    let zcol = col("_atom_site_fract_z").ok_or("atom-site loop is missing _atom_site_fract_z")?;
    let elcol = col("_atom_site_type_symbol")
        .or_else(|| col("_atom_site_label"))
        .ok_or("atom-site loop needs _atom_site_type_symbol or _atom_site_label")?;
    let occcol = col("_atom_site_occupancy");

    let mut asym = Vec::with_capacity(site_loop.rows.len());
    for (i, row) in site_loop.rows.iter().enumerate() {
        if let Some(oc) = occcol {
            let occ = num(&row[oc])?;
            if (occ - 1.0).abs() > 1e-3 {
                return Err(format!(
                    "atom {} has occupancy {}; partial occupancy/disorder is not supported",
                    i + 1, occ
                ));
            }
        }
        asym.push(AsymAtom {
            element: element_symbol(&row[elcol])?,
            frac: [wrap01(num(&row[xcol])?), wrap01(num(&row[ycol])?), wrap01(num(&row[zcol])?)],
        });
    }
    if asym.is_empty() {
        return Err("CIF atom-site loop has no rows".into());
    }

    // 3. Symmetry dispatch (priority order per the M4 design doc).
    let op_loop = find_loop(&cif, "_symmetry_equiv_pos_as_xyz")
        .or_else(|| find_loop(&cif, "_space_group_symop_operation_xyz"));

    if let Some((lp, opcol)) = op_loop {
        // Sub-path 1: apply the file's literal ops, return explicit atoms.
        let ops = lp.rows.iter().map(|row| parse_op(&row[opcol])).collect::<Result<Vec<_>, _>>()?;
        let mut atoms = Vec::new();
        for a in &asym {
            let mut orbit: Vec<[f64; 3]> = Vec::new();
            for op in &ops {
                let q = apply_op(op, a.frac);
                if !orbit.iter().any(|o| frac_close(*o, q)) {
                    orbit.push(q);
                }
            }
            for q in orbit {
                atoms.push(Atom { element: a.element.clone(), cart: frac_to_cart(&lattice, q), frac: Some(q) });
            }
        }
        let n = atoms.len();
        return Ok(Record {
            lattice: Some(lattice),
            atoms,
            spacegroup: None,
            asym_unit: None,
            bonds: None,
            meta: Meta { source_format: "cif".into(), n_atoms: n },
        });
    }

    if let Some(number) = spacegroup_number(&cif)? {
        // Sub-path 2: identifier only — Typst expands through wyckoff's tables.
        let n = asym.len();
        return Ok(Record {
            lattice: Some(lattice),
            atoms: vec![],
            spacegroup: Some(number),
            asym_unit: Some(asym),
            bonds: None,
            meta: Meta { source_format: "cif".into(), n_atoms: n },
        });
    }

    Err("CIF has neither a symmetry-op loop (_symmetry_equiv_pos_as_xyz / \
         _space_group_symop_operation_xyz) nor a spacegroup identifier \
         (_space_group_IT_number / _symmetry_Int_Tables_number / \
         _symmetry_space_group_name_H-M); cannot expand the structure"
        .into())
}

fn spacegroup_number(cif: &Cif) -> Result<Option<i64>, String> {
    for tag in ["_space_group_it_number", "_symmetry_int_tables_number"] {
        if let Some(v) = cif.scalars.get(tag) {
            let n: i64 = v.parse().map_err(|_| format!("{} value '{}' is not an integer", tag, v))?;
            if !(1..=230).contains(&n) {
                return Err(format!("{} must be 1..230, got {}", tag, n));
            }
            return Ok(Some(n));
        }
    }
    if let Some(v) = cif.scalars.get("_symmetry_space_group_name_h-m") {
        let norm: String = v.chars().filter(|c| !c.is_whitespace() && *c != '_' && *c != '\'' && *c != '"').collect();
        // Case-insensitive: real CIFs write H-M symbols in varied case
        // ('Fm-3m', 'F M -3 M', 'FM-3M'). The 230-symbol table is unique under
        // ASCII case-folding, so this adds no ambiguity.
        return match SG_SYMBOLS.iter().find(|(s, _)| s.eq_ignore_ascii_case(&norm)) {
            Some((_, n)) => Ok(Some(*n)),
            None => Err(format!(
                "unrecognized H-M spacegroup symbol '{}'; add an explicit _space_group_IT_number",
                v
            )),
        };
    }
    Ok(None)
}
