// expected: at or behind the perspective camera
#import "/lib.typ": camera, project
#let cam = camera(mode: "perspective", distance: 2.0)
#let _ = project(cam, (0.0, 100.0, 0.0))
