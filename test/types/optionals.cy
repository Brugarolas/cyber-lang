import test

-- Explicit type.
var a Option(int) = 123
test.eq(a == none, false)
test.eq(a != none, true)
test.eq(a.?, 123)

-- Shorthand. Wrap literal.
var b ?int = 123
test.eq(b.?, 123)

-- Wrap variable.
var ca = 123
var c ?int = ca
test.eq(c.?, 123)

-- Wrap object.
type Foo:
    a int
var d ?Foo = Foo{a: 123}
test.eq(d.?.a, 123)

-- Wrapping none implicitly.
b = none
test.eq(b == none, true)
test.eq(b != none, false)

-- Unwrap or default.
b = none
test.eq(b ?else 123, 123)
b = 234
test.eq(b ?else 123, 234)

--cytest: pass