#import "/lib.typ": prototypes, crystal
#set page(width: auto, height: auto, margin: 0.4cm)
#crystal(
  prototypes.perovskite("Sr", "Ti", "O", a: 3.905),
  bonds: ((elements: ("Ti", "O"), max: 2.2),),
  polyhedra: ("Ti",),
  width: 8cm,
)
