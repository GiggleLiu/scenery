//! Shared numeric helpers for the periodic-format parsers: cell-parameter ->
//! lattice-vector construction, cart<->frac conversion, fractional wrapping,
//! and a 3-float token reader. Lattice rows are the cell vectors a, b, c.

/// Build lattice vectors (rows) from cell parameters; angles in degrees.
/// Convention (must match wyckoff's Typst `lattice-vectors`): a along +x,
/// b in the xy-plane, c general:
///   v1 = (a, 0, 0)
///   v2 = (b·cos γ, b·sin γ, 0)
///   v3 = (c·cos β, c·(cos α − cos β·cos γ)/sin γ, sqrt(c² − v3x² − v3y²))
pub fn cell_to_vectors(a: f64, b: f64, c: f64, alpha: f64, beta: f64, gamma: f64) -> Result<[[f64; 3]; 3], String> {
    for (name, v) in [("a", a), ("b", b), ("c", c)] {
        if !(v.is_finite() && v > 0.0) {
            return Err(format!("cell length {} must be positive, got {}", name, v));
        }
    }
    let (ca, cb, cg) = (alpha.to_radians().cos(), beta.to_radians().cos(), gamma.to_radians().cos());
    let sg = gamma.to_radians().sin();
    if sg.abs() < 1e-9 {
        return Err("cell angle gamma must not be 0 or 180 degrees".into());
    }
    let cx = c * cb;
    let cy = c * (ca - cb * cg) / sg;
    let cz2 = c * c - cx * cx - cy * cy;
    if cz2 <= 0.0 {
        return Err(format!("cell angles ({}, {}, {}) are geometrically impossible", alpha, beta, gamma));
    }
    Ok([[a, 0.0, 0.0], [b * cg, b * sg, 0.0], [cx, cy, cz2.sqrt()]])
}

/// cart = fracᵀ · L, where lattice rows are the cell vectors.
pub fn frac_to_cart(l: &[[f64; 3]; 3], f: [f64; 3]) -> [f64; 3] {
    [0, 1, 2].map(|j| f[0] * l[0][j] + f[1] * l[1][j] + f[2] * l[2][j])
}

/// frac = L⁻¹ · cart (adjugate inverse, verified in Stage 1).
pub fn cart_to_frac(l: &[[f64; 3]; 3], c: [f64; 3]) -> Result<[f64; 3], String> {
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
    // inverse[i][j] = cof[j][i] / det
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

/// Wrap a fractional coordinate into [0, 1); snaps values within 1e-9 of 1 to 0
/// so symmetry-op images like 0.9999999999 deduplicate against 0.
pub fn wrap01(x: f64) -> f64 {
    let y = x.rem_euclid(1.0);
    if y > 1.0 - 1e-9 { 0.0 } else { y }
}

/// Read three finite floats from a whitespace token stream; `what` names the
/// line for error messages (e.g. "atom line 3", "lattice vector 2").
pub fn read3<'a>(it: &mut impl Iterator<Item = &'a str>, what: &str) -> Result<[f64; 3], String> {
    let mut v = [0.0f64; 3];
    for k in 0..3 {
        let tok = it.next().ok_or(format!("{} needs 3 numeric components", what))?;
        let x: f64 = tok.parse().map_err(|_| format!("bad number '{}' in {}", tok, what))?;
        if !x.is_finite() {
            return Err(format!("non-finite number '{}' in {}", tok, what));
        }
        v[k] = x;
    }
    Ok(v)
}
