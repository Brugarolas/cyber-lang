type S:
    a any

    func foo(self) int:
        return 123

var o = S{}
o.foo(234)

--cytest: error
--CompileError: Can not find compatible function for call: `foo(_, _)`.
--Functions named `foo` in `S`:
--    func foo(S) int
--
--main:8:1:
--o.foo(234)
--^
--