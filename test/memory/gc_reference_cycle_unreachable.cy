use t 'test'

-- GC is able to detect reference cycle.
func foo():
    var a = {_}
    var b = {_}
    a.append(b as any)
    b.append(a as any)
    var res = performGC()
    -- Cycle still alive in the current stack so no gc.
    t.eq(res['numCycFreed'], 0)
foo()
var res = performGC()
t.eq(res['numCycFreed'], 2)

-- Reference cycle with child non cyclable.
func foo2():
    var a = {_}
    var b = {_}
    a.append(b as any)
    b.append(a as any)
    a.append(pointer(void, 1))
foo2()
res = performGC()
t.eq(res['numCycFreed'], 2)

-- Reference cycle with non pool objects.
type T:
    a any
    b any
    c any
    d any
    e any
func foo3():
    var a = T{}
    var b = T{}
    a.c = b
    b.c = a
foo3()
res = performGC()
t.eq(res['numCycFreed'], 2)

--cytest: pass