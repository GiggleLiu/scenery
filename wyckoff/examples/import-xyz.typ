#import "/lib.typ": import-xyz, molecule, crystal

// A molecule straight from an .xyz file.
#molecule(import-xyz("/examples/data/water.xyz"), width: 5cm)

// A periodic cell straight from an extended-xyz file.
#crystal(import-xyz("/examples/data/si.extxyz"), width: 5cm)
