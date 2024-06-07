use a './test_mods/a.cy'
use t 'test'

-- Type alias of imported type.
type Vec2 = a.Vec2

-- Using alias as type spec.
type Parent:
    v Vec2

var v = Vec2{x=1, y=2}
t.eq(v.x, 1.0)
t.eq(v.y, 2.0)

func foo(v Vec2):
    pass

-- Using alias from imported module.
v = a.Vec2Alias{x=1, y=2}

-- Using alias from imported module as type spec.
type Parent2:
    v a.Vec2Alias

--cytest: pass