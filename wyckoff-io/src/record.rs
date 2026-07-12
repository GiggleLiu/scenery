use serde::Serialize;

#[derive(Serialize, Debug, PartialEq)]
pub struct Atom {
    pub element: String,
    pub cart: [f64; 3],
    #[serde(skip_serializing_if = "Option::is_none")]
    pub frac: Option<[f64; 3]>,
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
    pub asym_unit: Option<()>,
    pub bonds: Option<Vec<[usize; 2]>>,
    pub meta: Meta,
}
