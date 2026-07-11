// expected: must not contain `.`
#import "/lib.typ": sphere, build-scene
#build-scene(sphere((0, 0), 1, name: "a.b"))
