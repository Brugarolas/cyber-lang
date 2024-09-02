use t 'test'

-- Get runtime type.
t.eq(type(123), int)
var a = t.erase('abc')
t.eq(type(a), String)

-- id() for builtin types.
t.eq((any).id(), 10)
t.eq((bool).id(), 2)
t.eq((float).id(), 8)
t.eq((int).id(), 7)
t.eq((String).id(), 21)
t.eq((symbol).id(), 6)
t.eq((List[dyn]).id(), 13)
t.eq((Map).id(), 15)
t.eq((error).id(), 3)
t.eq((Fiber).id(), 23)
t.eq((type).id(), 11)

-- typeInfo()
t.assert(typeInfo(int).!int_t == IntInfo{
    sign = true,
    bits = 64,
})
t.assert(typeInfo(byte).!int_t == IntInfo{
    sign = false,
    bits = 8,
})
t.assert(typeInfo(float).!float_t == FloatInfo{
    bits = 64,
})
t.eq(typeInfo(bool).!bool_t, _)
t.eq(typeInfo(void).!void_t, _)
t.eq(typeInfo(type).!type_t, _)
t.eq(typeInfo(error).!error_t, _)
type Area trait:
    func area(self) float
t.assert(typeInfo(Area).!trait_t == TraitInfo{
    name = 'Area',
})
t.assert(typeInfo([10]int).!array_t == ArrayInfo{
    len  = 10,
    elem = int,
})
t.assert(typeInfo(?int).!opt_t == OptionInfo{
    elem = int
})
t.assert(typeInfo(*int).!ptr_t == PointerInfo{
    elem = int
})
type Shape enum:
    case rectangle Rectangle
    case line  float
    case point
type Rectangle:
    width  float
    height float
var choice_t = typeInfo(Shape).!choice_t
t.eq(choice_t.name.?, 'Shape')
t.eq(choice_t.cases.len(), 3)
t.eq(choice_t.cases[0].name, 'rectangle')
t.eq(choice_t.cases[0].type, Rectangle)
t.eq(choice_t.cases[1].name, 'line')
t.eq(choice_t.cases[1].type, float)
t.eq(choice_t.cases[2].name, 'point')
t.eq(choice_t.cases[2].type, void)
var enum_t = typeInfo(Shape.Tag).!enum_t
t.eq(enum_t.name.?, 'Tag')
t.eq(enum_t.cases.len(), 3)
t.eq(enum_t.cases[0].name, 'rectangle')
t.eq(enum_t.cases[1].name, 'line')
t.eq(enum_t.cases[2].name, 'point')
type O:
    a int
    b float
var object_t = typeInfo(O).!object_t
t.eq(object_t.name.?, 'O')
t.eq(object_t.fields.len(), 2)
t.eq(object_t.fields[0].name, 'a')
t.eq(object_t.fields[0].type, int)
t.eq(object_t.fields[1].name, 'b')
t.eq(object_t.fields[1].type, float)
type S struct:
    a int
    b float
var struct_t = typeInfo(S).!struct_t
t.eq(struct_t.name.?, 'S')
t.eq(struct_t.fields.len(), 2)
t.eq(struct_t.fields[0].name, 'a')
t.eq(struct_t.fields[0].type, int)
t.eq(struct_t.fields[1].name, 'b')
t.eq(struct_t.fields[1].type, float)
type FnPtr -> func(int, float) String
var func_t = typeInfo(FnPtr).!func_t
t.eq(func_t.kind, .ptr)
t.eq(func_t.ret, String)
t.eq(func_t.params.len(), 2)
t.eq(func_t.params[0].type, int)
t.eq(func_t.params[1].type, float)
type FnUnion -> Func(int, float) String
func_t = typeInfo(FnUnion).!func_t
t.eq(func_t.kind, .union)
t.eq(func_t.ret, String)
t.eq(func_t.params.len(), 2)
t.eq(func_t.params[0].type, int)
t.eq(func_t.params[1].type, float)

-- Referencing type name path.
use os
t.eq(type(os.CArray), type)

--cytest: pass