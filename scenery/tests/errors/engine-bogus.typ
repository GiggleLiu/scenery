// expected: engine must be "typst" or "wasm"
#import "/lib.typ": *
#let sc = build-scene(sphere((0, 0, 0), 1))
#render-scene(sc, camera(), engine: "gpu")
