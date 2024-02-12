import t 'test'

-- id()
t.eq(typeof(none).id(), 0)
t.eq(typeof(true).id(), 1)
t.eq(typeof(false).id(), 1)
t.eq(typeof(error.err).id(), 2)
t.eq(typeof('abc').id(), 18)
t.eq(typeof('abc🦊').id(), 18)
t.eq(typeof(.abc).id(), 6)
t.eq(typeof(123).id(), 7)
t.eq(typeof(123.0).id(), 8)
t.eq(typeof([]).id(), 10)
t.eq(typeof([:]).id(), 12)

-- Referencing type object.
type Foo:
    var a float
var foo = [Foo a: 123]
t.eq(typeof(foo), Foo)

-- Referencing builtin types.
t.eq((any).id(), 27)
t.eq((bool).id(), 1)
t.eq((float).id(), 8)
t.eq((int).id(), 7)
t.eq((String).id(), 18)
t.eq((Array).id(), 19)
t.eq((symbol).id(), 6)
t.eq((List).id(), 10)
t.eq((Map).id(), 12)
t.eq((pointer).id(), 23)
t.eq((error).id(), 2)
t.eq((Fiber).id(), 20)
t.eq((metatype).id(), 25)

-- Referencing type name path.
import os
t.eq(typesym(os.CArray), .metatype)

--cytest: pass