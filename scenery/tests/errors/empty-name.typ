// expected: object name must not be empty
#import "/lib.typ": sphere, build-scene
#build-scene(sphere((0, 0), 1, name: ""))
