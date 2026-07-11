// expected: object name must be a string
#import "/lib.typ": sphere, build-scene
#build-scene(sphere((0, 0), 1, name: 42))
