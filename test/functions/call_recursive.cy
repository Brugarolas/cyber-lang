use t 'test'

func fib(n int) int:
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)
var res = fib(6)
t.eq(res, 8)

-- Recursion with long lived object.
type S:
    n int
func foo2(o S) int:
    if o.n == 0:
        return 0
    var n = o.n
    o.n = o.n - 1
    return n + foo2(o)
t.eq(foo2(S{n=10}), 55) 

-- Recursion with new objects.
func foo3(o S) int:
    if o.n == 0:
        return 0
    return o.n + foo3(S{n=o.n - 1})
t.eq(foo3(S{n=10}), 55)

--cytest: pass