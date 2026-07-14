// expected: materia: duplicate energy-level id "same"
#import "/lib.typ": energy-level, orbital-column, mo-model
#let a = orbital-column("a", (energy-level("same", 0),))
#let b = orbital-column("b", (energy-level("same", 1),))
#mo-model((a, b))
