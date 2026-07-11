// expected: anchor reference cycle: a -> b -> a
#import "/lib.typ": sphere, build-scene, camera-2d, resolve-scene
#let scene = build-scene(
  sphere("b.center", 1, name: "a"),
  sphere("a.center", 1, name: "b"),
)
#resolve-scene(scene, camera-2d())
