use t 'test'

-- id()
t.eq(typeof(true).id(), 1)
t.eq(typeof(false).id(), 1)
t.eq(typeof(error.err).id(), 2)
t.eq(typeof('abc').id(), 21)
t.eq(typeof('abc🦊').id(), 21)
t.eq(typeof(symbol.abc).id(), 6)
t.eq(typeof(123).id(), 7)
t.eq(typeof(123.0).id(), 8)
t.eq(typeof({_}).id(), 13)
t.eq(typeof(Map{}).id(), 15)
t.eq(typeof({}).id(), 28)

-- Referencing type object.
type Foo:
    a float
var foo = Foo{a=123}
t.eq(typeof(foo), Foo)

-- Referencing builtin types.
t.eq((any).id(), 10)
t.eq((bool).id(), 1)
t.eq((float).id(), 8)
t.eq((int).id(), 7)
t.eq((String).id(), 21)
t.eq((Array).id(), 22)
t.eq((symbol).id(), 6)
t.eq((List[dyn]).id(), 13)
t.eq((Map).id(), 15)
t.eq((error).id(), 2)
t.eq((Fiber).id(), 23)
t.eq((metatype).id(), 26)

-- Referencing type name path.
use os
t.eq(typeof(os.CArray), metatype)

--cytest: pass