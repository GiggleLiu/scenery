//! Spatial-hash auto bond detection. Mirrors wyckoff's Typst `find-bonds`
//! (geometry.typ:85-111, `rules == auto` branch): a pair bonds iff
//!   d >= 0.4  &&  d <= 1.15 * (r_i + r_j),
//! with d = sqrt(dx*dx + dy*dy + dz*dz) accumulated in x, y, z order (mirrors
//! Typst `vlen`/`vdot`). Output is sorted ascending (i, j) with i < j -- exactly
//! the order the Typst `i`-outer/`j`-inner double loop emits.
//!
//! The radii come from the codegen'd `radii` table (same rounded r-cov as
//! elements.json), so the Rust and Typst rules can never drift.

use crate::radii::r_cov;
use std::collections::HashMap;

const BOND_SCALE: f64 = 1.15;
const MIN_DIST: f64 = 0.4;

/// Auto bond detection over a uniform spatial hash. `atoms` is `(element, cart)`
/// in input order; the returned index pairs reference that same order.
///
/// Atoms whose element has no covalent radius contribute no bonds (Typst would
/// have rejected the element upstream via `element-info`).
pub fn find_bonds(atoms: &[(String, [f64; 3])]) -> Vec<[usize; 2]> {
    // Per-atom radius (None -> atom never bonds).
    let rad: Vec<Option<f64>> = atoms.iter().map(|(el, _)| r_cov(el)).collect();

    // Max radius among atoms that actually have one. No radii -> no bonds.
    let r_max = rad.iter().filter_map(|r| *r).fold(0.0_f64, f64::max);
    if r_max <= 0.0 {
        return Vec::new();
    }

    // Cell size = the largest possible bond cutoff (1.15 * (r_max + r_max)).
    // Any bonded pair has d <= 1.15*(r_i+r_j) <= h, so both atoms fall in the
    // same or an adjacent cell -> the 27-cell scan sees every real bond.
    let h = BOND_SCALE * (2.0 * r_max);

    let key = |p: &[f64; 3]| -> (i64, i64, i64) {
        (
            (p[0] / h).floor() as i64,
            (p[1] / h).floor() as i64,
            (p[2] / h).floor() as i64,
        )
    };

    // Fill the grid in input order (values are input-order indices).
    let mut grid: HashMap<(i64, i64, i64), Vec<usize>> = HashMap::new();
    for (i, (_, cart)) in atoms.iter().enumerate() {
        grid.entry(key(cart)).or_default().push(i);
    }

    let mut out: Vec<[usize; 2]> = Vec::new();
    for (i, (_, ci)) in atoms.iter().enumerate() {
        let ri = match rad[i] {
            Some(r) => r,
            None => continue,
        };
        let (kx, ky, kz) = key(ci);
        // Scan the 27 neighbouring cells; test only j > i so each unordered
        // pair is seen exactly once (j lives in exactly one cell).
        for dx in -1..=1 {
            for dy in -1..=1 {
                for dz in -1..=1 {
                    if let Some(bucket) = grid.get(&(kx + dx, ky + dy, kz + dz)) {
                        for &j in bucket {
                            if j <= i {
                                continue;
                            }
                            let rj = match rad[j] {
                                Some(r) => r,
                                None => continue,
                            };
                            let cj = &atoms[j].1;
                            // dx,dy,dz order matches Typst vsub/vlen.
                            let ex = ci[0] - cj[0];
                            let ey = ci[1] - cj[1];
                            let ez = ci[2] - cj[2];
                            let d = (ex * ex + ey * ey + ez * ez).sqrt();
                            if d >= MIN_DIST && d <= BOND_SCALE * (ri + rj) {
                                out.push([i, j]);
                            }
                        }
                    }
                }
            }
        }
    }

    // Lexicographic [i, j] -- matches Typst's ascending i-outer/j-inner emission.
    // (NEVER iterate the HashMap for output: this sort makes the result
    // deterministic regardless of neighbour-cell visitation order.)
    out.sort();
    out
}
