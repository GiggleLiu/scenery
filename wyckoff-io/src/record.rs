use serde::Serialize;

#[derive(Serialize, Debug, PartialEq)]
pub struct Atom {
    pub element: String,
    pub cart: [f64; 3],
    #[serde(skip_serializing_if = "Option::is_none")]
    pub frac: Option<[f64; 3]>,
}

/// One asymmetric-unit atom, fractional coordinates. Returned only by the CIF
/// spacegroup-identifier path; wyckoff's Typst tables expand it.
#[derive(Serialize, Debug, PartialEq, Clone)]
pub struct AsymAtom {
    pub element: String,
    pub frac: [f64; 3],
}

#[derive(Serialize, Debug, PartialEq)]
pub struct Meta {
    pub source_format: String,
    pub n_atoms: usize,
}

#[derive(Serialize, Debug, PartialEq)]
pub struct Record {
    pub lattice: Option<[[f64; 3]; 3]>,
    pub atoms: Vec<Atom>,
    pub spacegroup: Option<i64>,
    // Serializes as null when None (no skip): the Typst consumer relies on the
    // key existing and JSON null decoding to `none`.
    pub asym_unit: Option<Vec<AsymAtom>>,
    pub bonds: Option<Vec<[usize; 2]>>,
    pub meta: Meta,
}
