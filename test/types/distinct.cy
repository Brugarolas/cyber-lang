use test

type Vec2:
    x float
    y float

type Vec Vec2:
    func add(self):
        return x + y

var v = Vec{x=1, y=2}
test.eq(v.x, 1.0)
test.eq(v.y, 2.0)
test.eq(v.add(), 3.0)

--cytest: pass