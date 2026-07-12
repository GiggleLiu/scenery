// expected: 3D anchor direction must not be zero
#import "/lib.typ": sphere, label, anchor-ref, build-scene, camera-2d, resolve-scene
#let scene = build-scene(
  sphere((0, 0), 1, name: "a"),
  label(anchor-ref("a", anchor: (0, 0, 0)), [bad]),
)
#resolve-scene(scene, camera-2d())
