type S:
    a float

func foo():
    return 123

var s = S{a=false}

--cytest: error
--CompileError: Expected type `float`, got `bool`.
--
--main:7:13:
--var s = S{a=false}
--            ^
--