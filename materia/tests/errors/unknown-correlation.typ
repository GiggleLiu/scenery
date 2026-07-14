// expected: materia: unknown correlation target "missing"
#import "/lib.typ": energy-level, orbital-column, correlate, mo-model
#let a = orbital-column("a", (energy-level("left", 0),))
#let b = orbital-column("b", (energy-level("right", 1),))
#mo-model((a, b), correlations: (correlate("left", "missing"),))
