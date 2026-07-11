// expected: duplicate object name
#import "/lib.typ": sphere, build-scene
#build-scene(sphere((0, 0), 1, name: "a"), sphere((2, 0), 1, name: "a"))
