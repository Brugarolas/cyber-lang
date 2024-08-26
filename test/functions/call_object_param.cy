use t 'test'

type Foo:
    a int

func foo(a Foo) bool:
    return a.a == 123

-- Literal.
t.eq(foo(Foo{a=123}), true)
        
-- From var.
var o = Foo{a=123}
t.eq(foo(o), true)

-- Cast erased type.
o = t.erase(Foo{a=123})
t.eq(foo(o as Foo), true)

--cytest: pass