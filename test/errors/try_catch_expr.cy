use t 'test'

func fail() dyn:
    throw error.Fail

func happy(a dyn) dyn:
    return a

-- Returns result.
var res = try 1 catch 0
t.eq(res, 1)

-- Top expr fails, returns default value.
res = try fail() catch 0
t.eq(res, 0)

-- Retained catch value.
var res2 = ''
res2 = try fail() catch 'retained'
t.eq(res2, 'retained')

-- Sub expr fails, returns default value.
res = try happy(fail()) catch 0
t.eq(res, 0)

--cytest: pass