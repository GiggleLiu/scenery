// expected: unknown object
#import "/lib.typ": seg, build-scene, camera-2d, resolve-scene
#let scene = build-scene(seg("missing", (1, 0), name: "bond"))
#resolve-scene(scene, camera-2d())
