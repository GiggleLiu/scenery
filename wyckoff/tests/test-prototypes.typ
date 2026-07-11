#import "/lib.typ": prototypes
#let p = prototypes

#assert(p.fcc("Cu", a: 3.61).atoms.len() == 4)
#assert(p.bcc("Fe", a: 2.87).atoms.len() == 2)
#assert(p.sc("Po", a: 3.35).atoms.len() == 1)
#assert(p.hcp("Mg", a: 3.21, c: 5.21).atoms.len() == 2)
#assert(p.diamond("Si", a: 5.43).atoms.len() == 8)
#assert(p.rocksalt("Na", "Cl", a: 5.64).atoms.len() == 8)
#assert(p.cesium-chloride("Cs", "Cl", a: 4.11).atoms.len() == 2)
#assert(p.zincblende("Ga", "As", a: 5.65).atoms.len() == 8)
#assert(p.wurtzite("Ga", "N", a: 3.19, c: 5.19).atoms.len() == 4)
#assert(p.fluorite("Ca", "F", a: 5.46).atoms.len() == 12)
#assert(p.rutile("Ti", "O", a: 4.59, c: 2.96).atoms.len() == 6)
#assert(p.perovskite("Sr", "Ti", "O", a: 3.905).atoms.len() == 5)
#assert(p.graphene().atoms.len() == 2)
#assert(p.hexagonal-bn().atoms.len() == 2)
#assert(p.tmd("Mo", "S", a: 3.16, z: 1.56).atoms.len() == 3)
Prototypes OK
