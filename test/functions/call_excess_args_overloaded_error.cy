func foo() int:
    return 1

func foo(n int) int:
    return n

foo(1, 2)

--cytest: error
--CompileError: Can not find compatible function for call: `foo(_, _)`.
--Functions named `foo` in `main`:
--    func foo() int
--    func foo(int) int
--
--main:7:1:
--foo(1, 2)
--^
--