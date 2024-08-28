#include <stdarg.h>
#include <string.h>
#include <stdio.h>
#include <math.h>
#include "vm.h"

// Dump assembly.
// zig cc -c src/vm.c -S -O2 -DDEBUG=0 -DCGOTO=1 -DTRACE=0 -DIS_32BIT=0 -DHAS_GC=1

#define STATIC_ASSERT(cond, msg) typedef char static_assertion_##msg[(cond)?1:-1]

#define TRACEV_IF(cond, msg, ...) \
    do { if (TRACE && clVerbose && cond) zLog(msg, (FmtValue[]){__VA_ARGS__}, sizeof((FmtValue[]){__VA_ARGS__})/sizeof(FmtValue)); } while (false)
#define TRACEV(msg, ...) \
    do { if (TRACE && clVerbose) zLog(msg, (FmtValue[]){__VA_ARGS__}, sizeof((FmtValue[]){__VA_ARGS__})/sizeof(FmtValue)); } while (false)
#define LTRACE(msg, ...) \
    do { if (TRACE) zLog(msg, (FmtValue[]){__VA_ARGS__}, sizeof((FmtValue[]){__VA_ARGS__})/sizeof(FmtValue)); } while (false)
#define LOG(msg, ...) \
    do { zLog(msg, (FmtValue[]){__VA_ARGS__}, sizeof((FmtValue[]){__VA_ARGS__})/sizeof(FmtValue)); } while (false)

#define ASSERT(cond) \
    do { if (!(cond)) zFatal(); } while (false)

#define FMT_STRZ(s) ((FmtValue){ .type = FMT_TYPE_STRING, .data = { .string = s }, .data2 = { .string = strlen(s) }})
#define FMT_STR(s) ((FmtValue){ .type = FMT_TYPE_STRING, .data = { .string = s.ptr }, .data2 = { .string = s.len }})
#define FMT_STRLEN(s, len) ((FmtValue){ .type = FMT_TYPE_STRING, .data = { .string = s }, .data2 = { .string = len }})
#define FMT_U32(v) ((FmtValue){ .type = FMT_TYPE_U32, .data = { .u32 = v }})
#define FMT_PTR(v) ((FmtValue){ .type = FMT_TYPE_PTR, .data = { .ptr = v }})

static inline TypeId getTypeId(Value val);

static inline Value objectGetField(Object* obj, uint8_t idx) {
    return (&obj->firstValue)[idx];
}

static inline Value* objectGetFieldPtr(Object* obj, uint8_t idx) {
    return (&obj->firstValue) + idx;
}

static inline Value* objectGetValuesPtr(Object* obj) {
    return &obj->firstValue;
}

static inline Value* closureGetCapturedValuesPtr(FuncUnion* closure) {
    return &closure->data.closure.firstCapturedVal;
}

static inline void release(VM* vm, Value val) {
#if TRACE
    vm->c.trace->numReleaseAttempts += 1;
#endif
    if (VALUE_IS_POINTER(val)) {
        HeapObject* obj = VALUE_AS_HEAPOBJECT(val);
        TRACEV_IF(LOG_MEM, "arc | {} -1 | {}, {}", FMT_U32(obj->head.rc), FMT_STR(zGetTypeName(vm, getTypeId(val))), FMT_PTR(obj));
#if TRACE
        zCheckDoubleFree(vm, obj);
#endif
        obj->head.rc -= 1;
#if TRACK_GLOBAL_RC
    #if TRACE
        if (vm->c.refCounts == 0) {
            LOG("Double free. {}", FMT_U32(getTypeId(val)));
            zFatal();
        }
    #endif
        vm->c.refCounts -= 1;
#endif
#if TRACE
        vm->c.trace->numReleases += 1;
#endif
        if (obj->head.rc == 0) {
            zFreeObject(vm, obj);
        }
    } else {
        TRACEV("release: {}, nop", FMT_STR(zGetTypeName(vm, getTypeId(val))));
    }
}

static inline void releaseObject(VM* vm, HeapObject* obj) {
    TRACEV_IF(LOG_MEM, "arc | {} -1 | {}, {}", FMT_U32(obj->head.rc), FMT_STR(zGetTypeName(vm, OBJ_TYPEID(obj))), FMT_PTR(obj));
#if (TRACE)
    zCheckDoubleFree(vm, obj);
#endif
    obj->head.rc -= 1;
#if TRACK_GLOBAL_RC
    #if TRACE
    if (vm->c.refCounts == 0) {
        LOG("Double free. {}", FMT_U32(OBJ_TYPEID(obj)));
        zFatal();
    }
    #endif
    vm->c.refCounts -= 1;
#endif
#if TRACE
    vm->c.trace->numReleases += 1;
    vm->c.trace->numReleaseAttempts += 1;
#endif
    if (obj->head.rc == 0) {
        zFreeObject(vm, obj);
    }
}

static inline void retainObject(VM* vm, HeapObject* obj) {
    TRACEV_IF(LOG_MEM, "arc | {} +1 | {}, {}", FMT_U32(obj->head.rc), FMT_STR(zGetTypeName(vm, OBJ_TYPEID(obj))), FMT_PTR(obj));
    obj->head.rc += 1;
#if TRACE
    zCheckRetainDanglingPointer(vm, obj);
#endif
#if TRACK_GLOBAL_RC
    vm->c.refCounts += 1;
#endif
#if TRACE
    vm->c.trace->numRetains += 1;
    vm->c.trace->numRetainAttempts += 1;
#endif
}

static inline void retain(VM* vm, Value val) {
#if TRACE
    vm->c.trace->numRetainAttempts += 1;
#endif
    if (VALUE_IS_POINTER(val)) {
        HeapObject* obj = VALUE_AS_HEAPOBJECT(val);
        TRACEV_IF(LOG_MEM, "arc | {} +1 | {}, {}", FMT_U32(obj->head.rc), FMT_STR(zGetTypeName(vm, getTypeId(val))), FMT_PTR(obj));
        obj->head.rc += 1;
#if TRACE
        zCheckRetainDanglingPointer(vm, obj);
#endif
#if TRACK_GLOBAL_RC
        vm->c.refCounts += 1;
#endif
#if TRACE
        vm->c.trace->numRetains += 1;
#endif
        // zTraceRetain(vm, val);
    } else {
        TRACEV("retain: {}, nop", FMT_STR(zGetTypeName(vm, getTypeId(val))));
    }
}

static inline double toF64(Value val) {
    if (VALUE_IS_FLOAT(val)) {
        return VALUE_AS_FLOAT(val);
    } else {
        return zOtherToF64(val);
    }
}

static inline TypeId getTypeId(Value val) {
    u64 bits = val & TAGGED_PRIMITIVE_MASK;
    if (bits >= TAGGED_VALUE_MASK) {
        // Tagged.
        if (VALUE_IS_POINTER(val)) {
            return OBJ_TYPEID(VALUE_AS_HEAPOBJECT(val));
        } else {
            if (bits >= TAGGED_ENUM_MASK) {
                return val & 0xffffffff;
            } else {
                return VALUE_GET_TAG(bits);
            }
        }
    } else {
        return TYPE_FLOAT;
    }
}

static inline uint32_t pcOffset(VM* vm, Inst* pc) {
    return (uintptr_t)pc - (uintptr_t)vm->c.instPtr;
}

static inline uint32_t stackOffset(VM* vm, Value* stack) {
    return ((uintptr_t)stack - (uintptr_t)vm->c.stackPtr) >> 3;
}

static inline bool isTypeCompat(TypeId typeId, TypeId cstrType) {
    if (typeId == cstrType) {
        return true;
    }
    if (cstrType == TYPE_ANY || cstrType == TYPE_DYN) {
        return true;
    }
    return false;
}

static inline ValueResult allocInt(VM* vm, i64 i) {
    HeapObjectResult res = zAllocPoolObject(vm);
    res.obj->integer = (Int){
        .typeId = TYPE_INTEGER,
        .rc = 1,
        .val = i,
    };
    return (ValueResult){ .val = VALUE_NOCYC_PTR(res.obj), .code = RES_CODE_SUCCESS };
}

static inline ValueResult allocStructSmall(VM* vm, TypeId typeId, Value* fields, u8* sizes, u8 numFields) {
    HeapObjectResult res = zAllocPoolObject(vm);
    if (UNLIKELY(res.code != RES_CODE_SUCCESS)) {
        return (ValueResult){ .code = res.code };
    }
    res.obj->object = (Object){
        .typeId = typeId | CYC_TYPE_MASK,
        .rc = 1,
    };

    Value* dst = objectGetValuesPtr(&res.obj->object);
    u8 offset = 0;
    for (int i = 0; i < numFields; i += 1) {
        u8 size = sizes[i];
        if (size > 0) {
            // Copy.
            HeapObject* field = VALUE_AS_HEAPOBJECT(fields[i]);
            Value* src = objectGetValuesPtr((Object*)field);
            memcpy(dst + offset, src, size * sizeof(Value));
            release(vm, fields[i]);
            offset += size;
        } else {
            dst[offset] = fields[i];
            offset += 1;
        }
    }

    return (ValueResult){ .val = VALUE_CYC_PTR(res.obj), .code = RES_CODE_SUCCESS };
}

static inline ValueResult allocStruct(VM* vm, TypeId typeId, Value* fields, u8* sizes, u8 numFields) {
    // First slot holds the typeId and rc.
    HeapObjectResult res = zAllocExternalCycObject(vm, (1 + numFields) * sizeof(Value));
    if (UNLIKELY(res.code != RES_CODE_SUCCESS)) {
        return (ValueResult){ .code = res.code };
    }
    res.obj->object = (Object){
        .typeId = typeId | CYC_TYPE_MASK,
        .rc = 1,
    };

    Value* dst = objectGetValuesPtr(&res.obj->object);
    u8 offset = 0;
    for (int i = 0; i < numFields; i += 1) {
        u8 size = sizes[i];
        if (size > 0) {
            // Copy.
            HeapObject* field = VALUE_AS_HEAPOBJECT(fields[i]);
            Value* src = objectGetValuesPtr((Object*)field);
            memcpy(dst + offset, src, size * sizeof(Value));
            offset += size;
        } else {
            dst[i] = fields[i];
            offset += 1;
        }
    }

    return (ValueResult){ .val = VALUE_CYC_PTR(res.obj), .code = RES_CODE_SUCCESS };
}

static inline ValueResult allocObjectSmall(VM* vm, TypeId typeId, Value* fields, u8 numFields) {
    HeapObjectResult res = zAllocPoolObject(vm);
    if (UNLIKELY(res.code != RES_CODE_SUCCESS)) {
        return (ValueResult){ .code = res.code };
    }
    res.obj->object = (Object){
        .typeId = typeId | CYC_TYPE_MASK,
        .rc = 1,
    };

    Value* dst = objectGetValuesPtr(&res.obj->object);
    memcpy(dst, fields, numFields * sizeof(Value));

    return (ValueResult){ .val = VALUE_CYC_PTR(res.obj), .code = RES_CODE_SUCCESS };
}

static inline ValueResult allocObject(VM* vm, TypeId typeId, Value* fields, u8 numFields) {
    // First slot holds the typeId and rc.
    HeapObjectResult res = zAllocExternalCycObject(vm, (1 + numFields) * sizeof(Value));
    if (UNLIKELY(res.code != RES_CODE_SUCCESS)) {
        return (ValueResult){ .code = res.code };
    }
    res.obj->object = (Object){
        .typeId = typeId | CYC_TYPE_MASK,
        .rc = 1,
    };

    Value* dst = objectGetValuesPtr(&res.obj->object);
    memcpy(dst, fields, numFields * sizeof(Value));

    return (ValueResult){ .val = VALUE_CYC_PTR(res.obj), .code = RES_CODE_SUCCESS };
}

static inline ValueResult allocTrait(VM* vm, TypeId typeId, u16 vtable, Value impl) {
    HeapObjectResult res = zAllocPoolObject(vm);
    if (UNLIKELY(res.code != RES_CODE_SUCCESS)) {
        return (ValueResult){ .code = res.code };
    }
    res.obj->trait = (Trait){
        .typeId = typeId | CYC_TYPE_MASK,
        .rc = 1,
        .impl = impl,
        .vtable = vtable,
    };
    return (ValueResult){ .val = VALUE_CYC_PTR(res.obj), .code = RES_CODE_SUCCESS };
}

static inline ValueResult allocEmptyMap(VM* vm) {
    HeapObjectResult res = zAllocPoolObject(vm);
    if (UNLIKELY(res.code != RES_CODE_SUCCESS)) {
        return (ValueResult){ .code = res.code };
    }
    res.obj->map = (Map){
        .typeId = TYPE_MAP | CYC_TYPE_MASK,
        .rc = 1,
        .inner = {
            .metadata = 0,
            .entries = 0,
            .size = 0,
            .cap = 0,
            .available = 0,
        },
    };
    return (ValueResult){ .val = VALUE_CYC_PTR(res.obj), .code = RES_CODE_SUCCESS };
}

static inline ValueResult allocFuncUnion(VM* vm, TypeId union_t, FuncPtr* func_ptr) {
    HeapObjectResult res = zAllocPoolObject(vm);
    if (UNLIKELY(res.code != RES_CODE_SUCCESS)) {
        return (ValueResult){ .code = res.code };
    }
    res.obj->func_union = (FuncUnion){
        .typeId = union_t | CYC_TYPE_MASK,
        .rc = 1,
        .numParams = func_ptr->numParams,
        .kind = func_ptr->kind,
        .reqCallTypeCheck = func_ptr->reqCallTypeCheck,
        .sig = func_ptr->sig,
        .data = func_ptr->data,
    };
    if (func_ptr->kind == 1 && func_ptr->data.host.has_tcc_state) {
        retain(vm, func_ptr->data.host.tcc_state);
    }
    return (ValueResult){ .val = VALUE_CYC_PTR(res.obj), .code = RES_CODE_SUCCESS };
}

static inline ValueResult allocFuncSym(VM* vm, TypeId sym_t, void* func) {
    HeapObjectResult res = zAllocPoolObject(vm);
    if (UNLIKELY(res.code != RES_CODE_SUCCESS)) {
        return (ValueResult){ .code = res.code };
    }
    res.obj->func_sym = (FuncSym){
        .typeId = sym_t,
        .rc = 1,
        .func = func,
    };
    return (ValueResult){ .val = VALUE_NOCYC_PTR(res.obj), .code = RES_CODE_SUCCESS };
}

static inline ValueResult allocUpValue(VM* vm, Value val) {
    HeapObjectResult res = zAllocPoolObject(vm);
    if (UNLIKELY(res.code != RES_CODE_SUCCESS)) {
        return (ValueResult){ .code = res.code };
    }
    res.obj->up = (UpValue){
        .typeId = TYPE_UPVALUE | CYC_TYPE_MASK,
        .rc = 1,
        .val = val,
    };
    return (ValueResult){ .val = VALUE_CYC_PTR(res.obj), .code = RES_CODE_SUCCESS };
}

static inline ValueResult allocExprType(VM* vm, uint32_t type_id) {
    HeapObjectResult res = zAllocPoolObject(vm);
    if (UNLIKELY(res.code != RES_CODE_SUCCESS)) {
        return (ValueResult){ .code = res.code };
    }
    res.obj->type = (Type){
        .typeId = TYPE_EXPRTYPE,
        .rc = 1,
        .type = type_id,
    };
    return (ValueResult){ .val = VALUE_NOCYC_PTR(res.obj), .code = RES_CODE_SUCCESS };
}

static inline ValueResult allocType(VM* vm, uint32_t type_id) {
    HeapObjectResult res = zAllocPoolObject(vm);
    if (UNLIKELY(res.code != RES_CODE_SUCCESS)) {
        return (ValueResult){ .code = res.code };
    }
    res.obj->type = (Type){
        .typeId = TYPE_TYPE,
        .rc = 1,
        .type = type_id,
    };
    return (ValueResult){ .val = VALUE_NOCYC_PTR(res.obj), .code = RES_CODE_SUCCESS };
}

// Exponentiation by squaring.
static i64 ipow(i64 b, i64 e) {
    if (e < 0) {
        if (b == 1 && e == -1) {
            return 1;
        }
        if (b == -1 && e == -1) {
            return  -1;
        }
        return 0;
    }
    i64 result = 1;
    for (;;) {
        if (e & 1) {
            result *= b;
        }
        e >>= 1;
        if (!e) {
            break;
        }
        b *= b;
    }
    return result;
}

static void panicStaticMsg(VM* vm, const char* msg) {
    vm->c.curFiber->panicPayload = (u64)msg | (((u64)(strlen(msg))) << 48);
    vm->c.curFiber->panicType = PANIC_STATIC_MSG;
    TRACEV("{}", FMT_STRZ(msg));
}

static inline void panicDivisionByZero(VM* vm) {
    panicStaticMsg(vm, "Division by zero.");
}

static inline void panicOutOfBounds(VM* vm) {
    panicStaticMsg(vm, "Out of bounds.");
}

static inline void panicExpectedInteger(VM* vm) {
    panicStaticMsg(vm, "Expected integer operand.");
}

static inline void panicFieldMissing(VM* vm) {
    panicStaticMsg(vm, "Field not found in value.");
}

static inline void panicUnexpectedChoice(VM* vm, i48 tag, i48 exp) {
    zPanicFmt(vm, "Expected active choice tag `{}`, found `{}`.", (FmtValue[]){
        FMT_U32((u32)exp), FMT_U32((u32)tag),
    }, 2);
}

static void panicIncompatibleType(VM* vm, TypeId actType, TypeId expType) {
    Str actTypeName = zGetTypeName(vm, actType);
    Str expTypeName = zGetTypeName(vm, expType);
    zPanicFmt(vm, "Expected type `{}`, found `{}`.", (FmtValue[]){
        FMT_STR(expTypeName), FMT_STR(actTypeName)
    }, 2);
}

static void panicIncompatibleFieldType(VM* vm, TypeId fieldTypeId, TypeId rightTypeId) {
    Str fieldTypeName = zGetTypeName(vm, fieldTypeId);
    Str rightTypeName = zGetTypeName(vm, rightTypeId);
    zPanicFmt(vm, "Assigning to `{}` field with incompatible type `{}`.", (FmtValue[]){
        FMT_STR(fieldTypeName), FMT_STR(rightTypeName)
    }, 2);
}

static void panicCastFail(VM* vm, TypeId actTypeId, TypeId expTypeId) {
    Str actName = zGetTypeName(vm, actTypeId);
    Str expName = zGetTypeName(vm, expTypeId);
    zPanicFmt(vm, "Can not cast `{}` to `{}`.", (FmtValue[]){
        FMT_STR(actName), FMT_STR(expName),
    }, 2);
}

#define RETURN(code) \
    do { \
        vm->c.curPc = pc; \
        vm->c.curStack = stack; \
        return code; \
    } while (false)

#define SAVE_STATE(code) \
    do { \
        vm->c.curPc = pc; \
        vm->c.curStack = stack; \
    } while (false)

#define RESTORE_STATE(code) \
    do { \
        pc = vm->c.curPc; \
        stack = vm->c.curStack; \
    } while (false)

#define INTEGER_UNOP(...) \
    i64 val = BITCAST(i64, stack[pc[1]]); \
    /* Body... */ \
    __VA_ARGS__; \
    pc += CALL_OBJ_SYM_INST_LEN; \
    NEXT(); \

#define INTEGER_BINOP(...) \
    i64 left = BITCAST(i64, stack[pc[1]]); \
    i64 right = BITCAST(i64, stack[pc[2]]); \
    /* Body... */ \
    __VA_ARGS__; \
    pc += CALL_OBJ_SYM_INST_LEN; \
    NEXT();

#define FLOAT_UNOP(...) \
    Value val = stack[pc[1]]; \
    /* Body... */ \
    __VA_ARGS__; \
    pc += CALL_OBJ_SYM_INST_LEN; \
    NEXT();

#define FLOAT_BINOP(...) \
    Value left = stack[pc[1]]; \
    Value right = stack[pc[2]]; \
    /* Body... */ \
    __VA_ARGS__; \
    pc += CALL_OBJ_SYM_INST_LEN; \
    NEXT();

ResultCode execBytecode(VM* vm) {
    #define READ_I16(offset) ((int16_t)(pc[offset] | ((uint16_t)pc[offset + 1] << 8)))
    #define READ_U16(offset) (pc[offset] | ((uint16_t)pc[offset + 1] << 8))
    #define WRITE_U16(offset, u) pc[offset] = u & 0xff; pc[offset+1] = u >> 8
    #define READ_U32(offset) ((uint32_t)pc[offset] | ((uint32_t)pc[offset+1] << 8) | ((uint32_t)pc[offset+2] << 16) | ((uint32_t)pc[offset+3] << 24))
    #define READ_U32_FROM(from, offset) ((uint32_t)from[offset] | ((uint32_t)from[offset+1] << 8) | ((uint32_t)from[offset+2] << 16) | ((uint32_t)from[offset+3] << 24))
    #define READ_U48(offset) ((uint64_t)pc[offset] | ((uint64_t)pc[offset+1] << 8) | ((uint64_t)pc[offset+2] << 16) | ((uint64_t)pc[offset+3] << 24) | ((uint64_t)pc[offset+4] << 32) | ((uint64_t)pc[offset+5] << 40))

#if TRACE
    #define PRE_TRACE() \
        vm->c.trace->opCounts[pc[0]].count += 1; \
        vm->c.trace->totalOpCounts += 1;
    #define PRE_DUMP() \
        if (clVerbose) { \
            zDumpEvalOp(vm, pc, stack); \
        } \
        vm->c.debugPc = pcOffset(vm, pc);
#else
    #define PRE_TRACE()
    #define PRE_DUMP()
#endif
#if CGOTO
    #define JENTRY(op) &&Code_##op
    static void* jumpTable[] = {
        JENTRY(ConstOp),
        JENTRY(ConstRetain),
        JENTRY(ConstIntV8),
        JENTRY(ConstByte),
        JENTRY(AddFloat),
        JENTRY(SubFloat),
        JENTRY(True),
        JENTRY(False),
        JENTRY(Not),
        JENTRY(None),
        JENTRY(Copy),
        JENTRY(CopyReleaseDst),
        JENTRY(CopyRetainSrc),
        JENTRY(CopyRetainRelease),
        JENTRY(CopyStruct),
        JENTRY(CopyObjDyn),
        JENTRY(SetIndexList),
        JENTRY(SetIndexMap),
        JENTRY(IndexList),
        JENTRY(IndexTuple),
        JENTRY(IndexMap),
        JENTRY(AppendList),
        JENTRY(ListDyn),
        JENTRY(List),
        JENTRY(Array),
        JENTRY(Map),
        JENTRY(SliceList),
        JENTRY(JumpNotCond),
        JENTRY(JumpCond),
        JENTRY(Jump),
        JENTRY(Release),
        JENTRY(ReleaseN),
        JENTRY(CallObjSym),
        JENTRY(CallObjNativeFuncIC),
        JENTRY(CallObjFuncIC),
        JENTRY(CallSym),
        JENTRY(CallFuncIC),
        JENTRY(CallNativeFuncIC),
        JENTRY(CallTrait),
        JENTRY(CallSymDyn),
        JENTRY(Ret1),
        JENTRY(Ret0),
        JENTRY(RetDyn),
        JENTRY(Call),
        JENTRY(TypeCheck),
        JENTRY(TypeCheckOption),
        JENTRY(FieldStruct),
        JENTRY(Field),
        JENTRY(FieldDyn),
        JENTRY(FieldDynIC),
        JENTRY(Lambda),
        JENTRY(Closure),
        JENTRY(Compare),
        JENTRY(LessFloat),
        JENTRY(GreaterFloat),
        JENTRY(LessEqualFloat),
        JENTRY(GreaterEqualFloat),
        JENTRY(LessInt),
        JENTRY(GreaterInt),
        JENTRY(LessEqualInt),
        JENTRY(GreaterEqualInt),
        JENTRY(MulFloat),
        JENTRY(DivFloat),
        JENTRY(PowFloat),
        JENTRY(ModFloat),
        JENTRY(CompareNot),
        JENTRY(StringTemplate),
        JENTRY(NegFloat),
        JENTRY(StructSmall),
        JENTRY(Struct),
        JENTRY(ObjectSmall),
        JENTRY(Object),
        JENTRY(Trait),
        JENTRY(Box),
        JENTRY(Unbox),
        JENTRY(AddrLocal),
        JENTRY(AddrConstIndex),
        JENTRY(AddrIndex),
        JENTRY(Deref),
        JENTRY(DerefStruct),
        JENTRY(SetDeref),
        JENTRY(SetDerefStruct),
        JENTRY(UnwrapChoice),
        JENTRY(SetFieldDyn),
        JENTRY(SetFieldDynIC),
        JENTRY(SetField),
        JENTRY(Catch),
        JENTRY(Throw),
        JENTRY(Coinit),
        JENTRY(Coyield),
        JENTRY(Coresume),
        JENTRY(Coreturn),
        JENTRY(Await),
        JENTRY(FutureValue),
        JENTRY(Retain),
        JENTRY(Up),
        JENTRY(SetUpValue),
        JENTRY(UpValue),
        JENTRY(Captured),
        JENTRY(SetCaptured),
        JENTRY(TagLit),
        JENTRY(Enum),
        JENTRY(Symbol),
        JENTRY(Cast),
        JENTRY(CastAbstract),
        JENTRY(BitwiseAnd),
        JENTRY(BitwiseOr),
        JENTRY(BitwiseXor),
        JENTRY(BitwiseNot),
        JENTRY(BitwiseLeftShift),
        JENTRY(BitwiseRightShift),
        JENTRY(AddInt),
        JENTRY(SubInt),
        JENTRY(MulInt),
        JENTRY(DivInt),
        JENTRY(PowInt),
        JENTRY(ModInt),
        JENTRY(NegInt),
        JENTRY(ForRangeInit),
        JENTRY(ForRange),
        JENTRY(ForRangeReverse),
        JENTRY(Match),
        JENTRY(FuncPtr),
        JENTRY(FuncUnion),
        JENTRY(FuncSym),
        JENTRY(StaticVar),
        JENTRY(SetStaticVar),
        JENTRY(Context),
        JENTRY(Type),
        JENTRY(End),
    };
    STATIC_ASSERT(sizeof(jumpTable) == (CodeEnd + 1) * sizeof(void*), JUMP_TABLE_INCOMPLETE);
    #define CASE(op) Code_##op
    #define NEXT() \
        do { \
            PRE_TRACE(); \
            PRE_DUMP(); \
            goto *jumpTable[*pc]; \
        } while (false)
#else
    // case name matches enum.
    #define CASE(op) case Code##op
    #define NEXT() \
        do { \
            PRE_TRACE(); \
            PRE_DUMP(); \
            goto beginSwitch \
        } while (false)
#endif

    register Inst* pc; 
    register Value* stack;

    pc = vm->c.curPc;
    stack = vm->c.curStack;

#if CGOTO
    // Goto first instruction.
    NEXT();
#else 
beginSwitch:
    switch ((OpCode)*pc) {
#endif
    CASE(ConstOp): {
        stack[pc[3]] = VALUE_RAW(vm->c.constPtr[READ_U16(1)]);
        pc += 4;
        NEXT();
    }
    CASE(ConstRetain): {
        Value val = VALUE_RAW(vm->c.constPtr[READ_U16(1)]);
        retain(vm, val);
        stack[pc[3]] = val;
        pc += 4;
        NEXT();
    }
    CASE(ConstIntV8): {
        i64 i = (i64)BITCAST(i8, pc[1]);
        stack[pc[2]] = BITCAST(u64, i);
        pc += 3;
        NEXT();
    }
    CASE(ConstByte): {
        u8 val = pc[1];
        stack[pc[2]] = val;
        pc += 3;
        NEXT();
    }
    CASE(AddFloat): {
        FLOAT_BINOP(stack[pc[3]] = VALUE_FLOAT(VALUE_AS_FLOAT(left) + VALUE_AS_FLOAT(right)))
    }
    CASE(SubFloat): {
        FLOAT_BINOP(stack[pc[3]] = VALUE_FLOAT(VALUE_AS_FLOAT(left) - VALUE_AS_FLOAT(right)))
    }
    CASE(True): {
        stack[pc[1]] = VALUE_TRUE;
        pc += 2;
        NEXT();
    }
    CASE(False): {
        stack[pc[1]] = VALUE_FALSE;
        pc += 2;
        NEXT();
    }
    CASE(Not): {
        Value val = stack[pc[1]];
#if TRACE
        if (!VALUE_IS_BOOLEAN(val)) {
            panicStaticMsg(vm, "Expected `bool` type.");
            RETURN(RES_CODE_PANIC);
        }
#endif
        bool bval = VALUE_AS_BOOLEAN(val);
        stack[pc[2]] = VALUE_BOOLEAN(!bval);
        pc += 3;
        NEXT();
    }
    CASE(None): {
        Value opt = stack[pc[1]];
#if TRACE
        TypeId typeId = getTypeId(opt);
        TypeEntry entry = vm->c.typesPtr[typeId];
        if (entry.kind != TYPE_KIND_OPTION) {
            TRACEV("Expected option value.");
            zFatal();
        }
#endif
        bool is_none = VALUE_AS_INTEGER(objectGetField((Object*)VALUE_AS_HEAPOBJECT(opt), 0)) == 0;
        stack[pc[2]] = VALUE_BOOLEAN(is_none);
        pc += 3;
        NEXT();
    }
    CASE(Copy):
        stack[pc[2]] = stack[pc[1]];
        pc += 3;
        NEXT();
    CASE(CopyReleaseDst): {
        u8 dst = pc[2];
        release(vm, stack[dst]);
        stack[dst] = stack[pc[1]];
        pc += 3;
        NEXT();
    }
    CASE(CopyRetainSrc): {
        Value val = stack[pc[1]];
        retain(vm, val);
        stack[pc[2]] = val;
        pc += 3;
        NEXT();
    }
    CASE(CopyRetainRelease): {
        retain(vm, stack[pc[1]]);
        release(vm, stack[pc[2]]);
        stack[pc[2]] = stack[pc[1]];
        pc += 3;
        NEXT();
    }
    CASE(CopyStruct): {
        HeapObject* obj = VALUE_AS_HEAPOBJECT(stack[pc[1]]);
        ValueResult res = zCopyStruct(vm, obj);
        if (res.code != RES_CODE_SUCCESS) {
            RETURN(res.code);
        }
        stack[pc[2]] = res.val;
        pc += 3;
        NEXT();
    }
    CASE(CopyObjDyn): {
        // Check that src is actually a value type.
        Value src = stack[pc[1]];
        TypeId typeId = getTypeId(src);
        TypeEntry entry = vm->c.typesPtr[typeId];
        if (entry.kind == TYPE_KIND_STRUCT) {
            u8 numFields = (u8)entry.data.object.numFields;
            HeapObject* obj = VALUE_AS_HEAPOBJECT(src);
            ValueResult res = zCopyStruct(vm, obj);
            if (res.code != RES_CODE_SUCCESS) {
                RETURN(res.code);
            }
            stack[pc[2]] = res.val;
        } else {
            stack[pc[2]] = src;
        }
        pc += 3;
        NEXT();
    }
    CASE(SetIndexList): {
        Value listv = stack[pc[1]];
        Value index = stack[pc[2]];
        Value right = stack[pc[3]];
        HeapObject* listo = VALUE_AS_HEAPOBJECT(listv);

        _BitInt(48) idx = VALUE_AS_INTEGER(index);
        if (idx >= 0 && idx < listo->list.list.len) {
            Value existing = ((Value*)listo->list.list.buf)[idx];
            release(vm, existing);
            retain(vm, right);
            ((Value*)listo->list.list.buf)[idx] = right;
            stack[pc[4]] = VALUE_VOID;
            pc += CALL_OBJ_SYM_INST_LEN;
            NEXT();
        } else {
            panicOutOfBounds(vm);
            RETURN(RES_CODE_PANIC);
        }
    }
    CASE(SetIndexMap): {
        Value mapv = stack[pc[1]];
        Value index = stack[pc[2]];
        Value right = stack[pc[3]];
        Map* mapo = (Map*)VALUE_AS_HEAPOBJECT(mapv);
        ResultCode code = zMapSet(vm, mapo, index, right);
        if (LIKELY(code == RES_CODE_SUCCESS)) {
            stack[pc[4]] = VALUE_VOID;
            pc += CALL_OBJ_SYM_INST_LEN;
            NEXT();
        }
        RETURN(code);
    }
    CASE(IndexList): {
        Value listv = stack[pc[1]];
        Value index = stack[pc[2]];
        HeapObject* listo = VALUE_AS_HEAPOBJECT(listv);

        _BitInt(48) idx = VALUE_AS_INTEGER(index);
        if (idx >= 0 && idx < listo->list.list.len) {
            Value val = ((Value*)listo->list.list.buf)[idx];
            retain(vm, val);
            stack[pc[3]] = val;
            pc += CALL_OBJ_SYM_INST_LEN;
            NEXT();
        } else {
            panicOutOfBounds(vm);
            RETURN(RES_CODE_PANIC);
        }
    }
    CASE(IndexTuple): {
        Value tuplev = stack[pc[1]];
        Value index = stack[pc[2]];
        Tuple* tuple = (Tuple*)VALUE_AS_HEAPOBJECT(tuplev);

        _BitInt(48) idx = VALUE_AS_INTEGER(index);
        if (idx < 0) {
            // Reverse index.
            idx = tuple->len + idx;
        }
        if (idx >= 0 && idx < tuple->len) {
            Value val = ((Value*)&tuple->firstValue)[idx];
            retain(vm, val);
            stack[pc[3]] = val;
            pc += CALL_OBJ_SYM_INST_LEN;
            NEXT();
        } else {
            panicOutOfBounds(vm);
            RETURN(RES_CODE_PANIC);
        }
    }
    CASE(IndexMap): {
        Value mapv = stack[pc[1]];
        Value index = stack[pc[2]];
        HeapObject* mapo = VALUE_AS_HEAPOBJECT(mapv);
        bool found;
        Value val = zValueMapGet(&mapo->map.inner, index, &found);
        if (found) {
            retain(vm, val);
            stack[pc[3]] = val;
        } else {
            panicFieldMissing(vm);
            RETURN(RES_CODE_PANIC);
        }
        pc += CALL_OBJ_SYM_INST_LEN;
        NEXT();
    }
    CASE(AppendList): {
        Value listv = stack[pc[1]];
        Value itemv = stack[pc[2]];

        HeapObject* listo = VALUE_AS_HEAPOBJECT(listv);

        size_t len = listo->list.list.len;
        if (len == listo->list.list.cap) {
            // ensure cap.
            ResultCode code = zEnsureListCap(vm, &listo->list.list, len + 1);
            if (code != RES_CODE_SUCCESS) {
                RETURN(code);
            }
        }

        retain(vm, itemv);
        ((Value*)listo->list.list.buf)[len] = itemv;
        listo->list.list.len = len + 1;
        stack[pc[3]] = VALUE_VOID;

        pc += CALL_OBJ_SYM_INST_LEN;
        NEXT();
    }
    CASE(ListDyn): {
        u8 startLocal = pc[1];
        u8 numElems = pc[2];
        ValueResult res = zAllocListDyn(vm, stack + startLocal, numElems);
        if (UNLIKELY(res.code != RES_CODE_SUCCESS)) {
            RETURN(res.code);
        }
        stack[pc[3]] = res.val;
        pc += 4;
        NEXT();
    }
    CASE(List): {
        u8 startLocal = pc[1];
        u8 numElems = pc[2];
        u16 type_id = READ_U16(3);
        ValueResult res = zAllocList(vm, type_id, stack + startLocal, numElems);
        if (UNLIKELY(res.code != RES_CODE_SUCCESS)) {
            RETURN(res.code);
        }
        stack[pc[5]] = res.val;
        pc += 6;
        NEXT();
    }
    CASE(Array): {
        u8 startLocal = pc[1];
        u8 numElems = pc[2];
        u16 type_id = READ_U16(3);
        ValueResult res = zAllocArray(vm, type_id, stack + startLocal, numElems);
        if (UNLIKELY(res.code != RES_CODE_SUCCESS)) {
            RETURN(res.code);
        }
        stack[pc[5]] = res.val;
        pc += 6;
        NEXT();
    }
    CASE(Map): {
        ValueResult res = allocEmptyMap(vm);
        if (UNLIKELY(res.code != RES_CODE_SUCCESS)) {
            RETURN(res.code);
        }
        stack[pc[1]] = res.val;
        pc += 2;
        NEXT();
    }
    CASE(SliceList): {
        Value listv = stack[pc[1]];
        Value rangev = stack[pc[2]];
        HeapObject* listo = VALUE_AS_HEAPOBJECT(listv);
        HeapObject* rangeo = VALUE_AS_HEAPOBJECT(rangev);

        i64 start = rangeo->range.start;
        if (start < 0) {
            panicOutOfBounds(vm);
            RETURN(RES_CODE_PANIC);
        }

        i64 end = rangeo->range.end;
        if (end > listo->list.list.len) {
            panicOutOfBounds(vm);
            RETURN(RES_CODE_PANIC);
        }

        if (end < start) {
            panicOutOfBounds(vm);
            RETURN(RES_CODE_PANIC);
        }

        Value* elems = ((Value*)listo->list.list.buf);
        for (int i = start; i < end; i += 1) {
            retain(vm, elems[i]);
        }
        ValueResult res = zAllocListDyn(vm, elems + start, end - start);
        if (UNLIKELY(res.code != RES_CODE_SUCCESS)) {
            RETURN(res.code);
        }
        stack[pc[3]] = res.val;
        pc += CALL_OBJ_SYM_INST_LEN;
        NEXT();
    }
    CASE(JumpNotCond): {
        Value condv = stack[pc[1]];
#if TRACE
        if (!VALUE_IS_BOOLEAN(condv)) {
            panicStaticMsg(vm, "Unexpected. Insert type check.");
            RETURN(RES_CODE_PANIC);
        }
#endif
        bool cond = VALUE_AS_BOOLEAN(condv);
        if (!cond) {
            pc += READ_U16(2);
            NEXT();
        } else {
            pc += 4;
            NEXT();
        }
    }
    CASE(JumpCond): {
        Value condv = stack[pc[1]];
#if TRACE
        if (!VALUE_IS_BOOLEAN(condv)) {
            panicStaticMsg(vm, "Unexpected. Insert type check.");
            RETURN(RES_CODE_PANIC);
        }
#endif
        bool cond = VALUE_AS_BOOLEAN(condv);
        if (cond) {
            pc += (uintptr_t)READ_I16(2);
        } else {
            pc += 4;
        }
        NEXT();
    }
    CASE(Jump): {
        pc += READ_I16(1);
        NEXT();
    }
    CASE(Release): {
        release(vm, stack[pc[1]]);
        pc += 2;
        NEXT();
    }
    CASE(ReleaseN): {
        u8 numLocals = pc[1];
        u8 i;
        for (i = 2; i < 2 + numLocals; i += 1) {
            TRACEV("release reg {}", FMT_U32(pc[i]));
            release(vm, stack[pc[i]]);
        }
        pc += 2 + numLocals;
        NEXT();
    }
    CASE(CallObjSym): {
        #if TRACE
            vm->c.trace_indent += 1;
        #endif
        u8 ret = pc[1];
        u8 numArgs = pc[2];
        u16 method = READ_U16(4);

        Value recv = stack[ret + CALL_ARG_START];
        TypeId typeId = getTypeId(recv);

        CallObjSymResult res = zCallObjSym(vm, pc, stack, recv, typeId, method, ret, numArgs);
        if (res.code != RES_CODE_SUCCESS) {
            RETURN(res.code);
        }
        pc = res.pc;
        stack = res.stack;
        NEXT();
    }
    CASE(CallObjNativeFuncIC): {
        u8 ret = pc[1];
        u8 numArgs = pc[2];
        Value recv = stack[ret + CALL_ARG_START];
        TypeId typeId = getTypeId(recv);

        TypeId cachedTypeId = READ_U16(14);
        if (typeId == cachedTypeId) {
            #if TRACE
                vm->c.trace_indent += 1;
            #endif
            vm->c.curPc = pc;
            vm->c.curStack = stack + ret;
            HostFuncFn fn = (HostFuncFn)READ_U48(8);
            Value res = fn(vm);
            if (res == VALUE_INTERRUPT) {
                RETURN(RES_CODE_PANIC);
            }
            stack[ret] = res;
            pc += CALL_OBJ_SYM_INST_LEN;
            
            #if TRACE
                vm->c.trace_indent -= 1;
            #endif
            NEXT();
        }

        // Deoptimize.
        pc[0] = CodeCallObjSym;
        NEXT();
    }
    CASE(CallObjFuncIC): {
        u8 ret = pc[1];
        Value recv = stack[ret + CALL_ARG_START];
        TypeId typeId = getTypeId(recv);

        TypeId cachedTypeId = READ_U16(14);
        if (typeId == cachedTypeId) {
            // Deoptimize.
            pc[0] = CodeCallObjSym;
            NEXT();
        }

        #if TRACE
            vm->c.trace_indent += 1;
        #endif

        // TODO: Split into CallObjTypedFuncIC where cached func sig id is used instead.
        // const callFuncSig = vm.sema.getFuncSig(callSigId);
        // for (1..callFuncSig.paramLen) |i| {
        //     if (!types.isTypeSymCompat(vm.compiler, callFuncSig.paramPtr[i], targetSig.paramPtr[i])) {
        //         return false;
        //     }
        // }

        u8 numLocals = pc[7];
        if (stack + ret + numLocals >= vm->c.stackEndPtr) {
            RETURN(RES_CODE_STACK_OVERFLOW);
        }
        Value retFramePtr = (uintptr_t)stack;
        stack += ret;
        stack[1] = VALUE_CALLINFO(false, CALL_OBJ_SYM_INST_LEN, numLocals);
        stack[2] = (uintptr_t)(pc + CALL_OBJ_SYM_INST_LEN);
        stack[3] = retFramePtr;
        pc = vm->c.instPtr + READ_U32(8);
        NEXT();
    }
    CASE(CallSym): {
        #if TRACE
            vm->c.trace_indent += 1;
        #endif
        u8 ret = pc[1];
        u8 numArgs = pc[2];
        u16 symId = READ_U16(4);
        PcFpResult res = zCallSym(vm, pc, stack, symId, ret);
        if (res.code != RES_CODE_SUCCESS) {
            RETURN(res.code);
        }
        pc = res.pc;
        stack = res.fp;
        NEXT();
    }
    CASE(CallFuncIC): {
        #if TRACE
            vm->c.trace_indent += 1;
        #endif
        u8 ret = pc[1];
        u8 numLocals = pc[4];
        if (stack + ret + numLocals >= vm->c.stackEndPtr) {
            RETURN(RES_CODE_STACK_OVERFLOW);
        }

        Value retFramePtr = (uintptr_t)stack;
        stack += ret;
        stack[1] = VALUE_CALLINFO(false, CALL_SYM_INST_LEN, numLocals);
        stack[2] = (uintptr_t)(pc + CALL_SYM_INST_LEN);
        stack[3] = retFramePtr;
        pc = (Inst*)READ_U48(6);
        NEXT();
    }
    CASE(CallNativeFuncIC): {
        #if TRACE
            vm->c.trace_indent += 1;
        #endif
        u8 ret = pc[1];
        u8 numArgs = pc[2];

        vm->c.curPc = pc;
        vm->c.curStack = stack + ret;
        HostFuncFn fn = (HostFuncFn)READ_U48(6);
        Value res = fn(vm);
        if (res == VALUE_INTERRUPT) {
            RETURN(RES_CODE_PANIC);
        }
        stack[ret] = res;
        pc += CALL_SYM_INST_LEN;
        #if TRACE
            vm->c.trace_indent -= 1;
        #endif
        NEXT();
    }
    CASE(CallTrait): {
        #if TRACE
            vm->c.trace_indent += 1;
        #endif
        u8 ret = pc[1];
        u8 nargs = pc[2];
        u16 vtable_idx = READ_U16(4);
        PcFpResult res = zCallTrait(vm, pc, stack, vtable_idx, ret);
        if (res.code != RES_CODE_SUCCESS) {
            RETURN(res.code);
        }
        pc = res.pc;
        stack = res.fp;
        NEXT();
    }
    CASE(CallSymDyn): {
        #if TRACE
            vm->c.trace_indent += 1;
        #endif
        u8 ret = pc[1];
        u8 nargs = pc[2];
        u16 entry = READ_U16(4);
        PcFpResult res = zCallSymDyn(vm, pc, stack, entry, ret, nargs);
        if (res.code != RES_CODE_SUCCESS) {
            RETURN(res.code);
        }
        pc = res.pc;
        stack = res.fp;
        NEXT();
    }
    CASE(Ret1): {
        #if TRACE
            vm->c.trace_indent -= 1;
        #endif
        u8 retFlag = VALUE_CALLINFO_RETFLAG(stack[1]);
        if (retFlag == 0) {
            pc = (Inst*)stack[2];
            stack = (Value*)stack[3];
            NEXT();
        } else {
            RETURN(RES_CODE_SUCCESS);
        }
    }
    CASE(Ret0): {
        #if TRACE
            vm->c.trace_indent -= 1;
        #endif
        u8 retFlag = VALUE_CALLINFO_RETFLAG(stack[1]);
        stack[0] = VALUE_VOID;
        if (retFlag == 0) {
            pc = (Inst*)stack[2];
            stack = (Value*)stack[3];
            NEXT();
        } else {
            RETURN(RES_CODE_SUCCESS);
        }
    }
    CASE(RetDyn): {
        u8 ret_flag = VALUE_CALLINFO_RETFLAG(stack[1]);
        u8 nargs = pc[1];
        u32 ret_type_mask = stack[1] >> 32;
        TypeId ret_t = ret_type_mask & 0x7fffffff;
        bool box = (ret_type_mask & 0x80000000) != 0;
        if (box) {
            stack[0] = zBox(vm, stack[5+nargs], ret_t);
        } else {
            stack[0] = stack[5+nargs];
        }
        if (ret_flag == 0) {
            pc = (Inst*)stack[2];
            stack = (Value*)stack[3];
            NEXT();
        } else {
            RETURN(RES_CODE_SUCCESS);
        }
    }
    CASE(Call): {
        #if TRACE
            vm->c.trace_indent += 1;
        #endif
        u8 ret = pc[1];
        u8 numArgs = pc[2];

        Value callee = stack[ret + CALLEE_START];
        PcFpResult res = zCall(vm, pc, stack, callee, ret, numArgs);
        if (LIKELY(res.code == RES_CODE_SUCCESS)) {
            pc = res.pc;
            stack = res.fp;
            NEXT();
        }
        RETURN(res.code);
    }
    CASE(TypeCheck): {
        Value val = stack[pc[1]];
        TypeId expType = (TypeId)READ_U16(2);
        TypeId actType = getTypeId(val);
        if (!isTypeCompat(actType, expType)) {
            panicIncompatibleType(vm, actType, expType);
            RETURN(RES_CODE_PANIC);
        }
        stack[pc[4]] = val;
        pc += 5;
        NEXT();
    }
    CASE(TypeCheckOption): {
        Value val = stack[pc[1]];
        TypeId typeId = getTypeId(val);
        TypeEntry entry = vm->c.typesPtr[typeId];
        if (entry.kind != TYPE_KIND_OPTION) {
            panicStaticMsg(vm, "Expected `Option` type.");
            RETURN(RES_CODE_PANIC);
        }
        pc += 2;
        NEXT();
    }
    CASE(FieldStruct): {
        Value recv = stack[pc[1]];
        u16 type_id = READ_U16(2);
        HeapObject* obj = VALUE_AS_HEAPOBJECT(recv);
        Value* start = objectGetFieldPtr((Object*)obj, pc[3]);
        u8 size = pc[4];
        ValueResult res;
        if (size <= 4) {
            res = allocObjectSmall(vm, type_id, start, size);
        } else {
            res = allocObject(vm, type_id, start, size);
        }
        if (res.code != RES_CODE_SUCCESS) {
            RETURN(res.code);
        }
        stack[pc[5]] = res.val;
        pc += 6;
        NEXT();
    }
    CASE(Field): {
        Value recv = stack[pc[1]];
        HeapObject* obj = VALUE_AS_HEAPOBJECT(recv);
        bool retain_flag = pc[3];
        stack[pc[4]] = objectGetField((Object*)obj, pc[2]);
        if (retain_flag) {
            retain(vm, stack[pc[4]]);
        }
        pc += 5;
        NEXT();
    }
    CASE(FieldDyn): {
        u8 left = pc[1];
        u8 dst = pc[2];
        u16 field_id = READ_U16(3);
        Value recv = stack[left];
        if (!VALUE_IS_POINTER(recv)) {
            panicFieldMissing(vm);
            RETURN(RES_CODE_PANIC);
        }
        HeapObject* obj = VALUE_AS_HEAPOBJECT(recv);
        TypeField res = zGetTypeField(vm, OBJ_TYPEID(obj), field_id);
        if (res.offset != NULL_U16) {
            Value field = objectGetField((Object*)obj, res.offset);
            if (res.boxed) {
                retain(vm, field);
                stack[dst] = field;
            } else {
                stack[dst] = zBox(vm, field, res.type_id);
            }
            pc[0] = CodeFieldDynIC;
            WRITE_U16(5, OBJ_TYPEID(obj));
            pc[7] = (u8)res.offset;
            pc[8] = res.boxed;
            WRITE_U16(9, res.type_id);
        } else {
            SAVE_STATE();
            Value res = zGetFieldFallback(vm, obj, field_id);
            if (res == VALUE_INTERRUPT) {
                RESTORE_STATE();
                RETURN(RES_CODE_PANIC);
            }
            stack[dst] = res;
        }
        pc += 11;
        NEXT();
    }
    CASE(FieldDynIC): {
        Value recv = stack[pc[1]];
        u8 dst = pc[2];
        if (!VALUE_IS_POINTER(recv)) {
            panicFieldMissing(vm);
            RETURN(RES_CODE_PANIC);
        }
        HeapObject* obj = VALUE_AS_HEAPOBJECT(recv);
        if (OBJ_TYPEID(obj) == READ_U16(5)) {
            Value field = objectGetField((Object*)obj, pc[7]);
            if (pc[8]) {
                retain(vm, field);
                stack[dst] = field;
            } else {
                stack[dst] = zBox(vm, field, READ_U16(9));
            }
            pc += 11;
            NEXT();
        } else {
            // Deoptimize.
            pc[0] = CodeFieldDyn;
            NEXT();
        }
    }
    CASE(Lambda): {
        u16 func_id = READ_U16(1);
        u16 ptr_t = READ_U16(3);
        ValueResult res = zAllocLambda(vm, func_id, ptr_t);
        if (res.code != RES_CODE_SUCCESS) {
            RETURN(res.code);
        }
        stack[pc[5]] = res.val;
        pc += 6;
        NEXT();
    }
    CASE(Closure): {
        u16 func_id = READ_U16(1);
        u16 union_t = READ_U16(3);
        u8 numCaptured = pc[5];
        u8 local = pc[6];
        u8 dst = pc[7];
        Inst* capturedVals = pc + 8;

        ValueResult res = zAllocClosure(vm, stack, func_id, union_t, capturedVals, numCaptured, local);
        if (res.code != RES_CODE_SUCCESS) {
            RETURN(res.code);
        }
        stack[dst] = res.val;
        pc += 8 + numCaptured;
        NEXT();
    }
    CASE(Compare): {
        Value left = stack[pc[1]];
        Value right = stack[pc[2]];
        if (left == right) {
            stack[pc[3]] = VALUE_TRUE;
        } else {
            stack[pc[3]] = zEvalCompare(left, right);
        }
        pc += 4;
        NEXT();
    }
    CASE(LessFloat): {
        FLOAT_BINOP(stack[pc[3]] = VALUE_BOOLEAN(VALUE_AS_FLOAT(left) < VALUE_AS_FLOAT(right)))
    }
    CASE(GreaterFloat): {
        FLOAT_BINOP(stack[pc[3]] = VALUE_BOOLEAN(VALUE_AS_FLOAT(left) > VALUE_AS_FLOAT(right)))
    }
    CASE(LessEqualFloat): {
        FLOAT_BINOP(stack[pc[3]] = VALUE_BOOLEAN(VALUE_AS_FLOAT(left) <= VALUE_AS_FLOAT(right)))
    }
    CASE(GreaterEqualFloat): {
        FLOAT_BINOP(stack[pc[3]] = VALUE_BOOLEAN(VALUE_AS_FLOAT(left) >= VALUE_AS_FLOAT(right)))
    }
    CASE(LessInt): {
        INTEGER_BINOP(stack[pc[3]] = VALUE_BOOLEAN(left < right))
    }
    CASE(GreaterInt): {
        INTEGER_BINOP(stack[pc[3]] = VALUE_BOOLEAN(left > right))
    }
    CASE(LessEqualInt): {
        INTEGER_BINOP(stack[pc[3]] = VALUE_BOOLEAN(left <= right))
    }
    CASE(GreaterEqualInt): {
        INTEGER_BINOP(stack[pc[3]] = VALUE_BOOLEAN(left >= right))
    }
    CASE(MulFloat): {
        FLOAT_BINOP(stack[pc[3]] = VALUE_FLOAT(VALUE_AS_FLOAT(left) * VALUE_AS_FLOAT(right)))
    }
    CASE(DivFloat): {
        FLOAT_BINOP(stack[pc[3]] = VALUE_FLOAT(VALUE_AS_FLOAT(left) / VALUE_AS_FLOAT(right)))
    }
    CASE(PowFloat): {
        FLOAT_BINOP(stack[pc[3]] = VALUE_FLOAT(pow(VALUE_AS_FLOAT(left), VALUE_AS_FLOAT(right))))
    }
    CASE(ModFloat): {
        FLOAT_BINOP(stack[pc[3]] = VALUE_FLOAT(fmod(VALUE_AS_FLOAT(left), VALUE_AS_FLOAT(right))))
    }
    CASE(CompareNot): {
        Value left = stack[pc[1]];
        Value right = stack[pc[2]];
        if (left == right) {
            stack[pc[3]] = VALUE_FALSE;
        } else {
            stack[pc[3]] = zEvalCompareNot(left, right);
        }
        pc += 4;
        NEXT();
    }
    CASE(StringTemplate): {
        u8 startLocal = pc[1];
        u8 exprCount = pc[2];
        u8 dst = pc[3];
        u8 strCount = exprCount + 1;
        Inst* strs = pc + 4;
        Value* vals = stack + startLocal;
        ValueResult res = zAllocStringTemplate(vm, strs, strCount, vals, exprCount);
        if (LIKELY(res.code == RES_CODE_SUCCESS)) {
            stack[dst] = res.val;
            pc += 4 + strCount;
            NEXT();
        }
        RETURN(res.code);
    }
    CASE(NegFloat): {
        FLOAT_UNOP(stack[pc[2]] = VALUE_FLOAT(-VALUE_AS_FLOAT(val)))
    }
    CASE(StructSmall): {
        u16 typeId = READ_U16(1);
        u8 startLocal = pc[3];
        u8 numFields = pc[4];
        ValueResult res = allocStructSmall(vm, typeId, stack + startLocal, pc + 6, numFields);
        if (res.code != RES_CODE_SUCCESS) {
            RETURN(res.code);
        }
        stack[pc[5]] = res.val;
        pc += 6 + numFields;
        NEXT();
    }
    CASE(Struct): {
        u16 typeId = READ_U16(1);
        u8 startLocal = pc[3];
        u8 numFields = pc[4];
        ValueResult res = allocStruct(vm, typeId, stack + startLocal, pc + 6, numFields);
        if (res.code != RES_CODE_SUCCESS) {
            RETURN(res.code);
        }
        stack[pc[5]] = res.val;
        pc += 6 + numFields;
        NEXT();
    }
    CASE(ObjectSmall): {
        u16 typeId = READ_U16(1);
        u8 startLocal = pc[3];
        u8 numFields = pc[4];
        ValueResult res = allocObjectSmall(vm, typeId, stack + startLocal, numFields);
        if (res.code != RES_CODE_SUCCESS) {
            RETURN(res.code);
        }
        stack[pc[5]] = res.val;
        pc += 6;
        NEXT();
    }
    CASE(Object): {
        u16 typeId = READ_U16(1);
        u8 startLocal = pc[3];
        u8 numFields = pc[4];
        ValueResult res = allocObject(vm, typeId, stack + startLocal, numFields);
        if (res.code != RES_CODE_SUCCESS) {
            RETURN(res.code);
        }
        stack[pc[5]] = res.val;
        pc += 6;
        NEXT();
    }
    CASE(Trait): {
        Value impl = stack[pc[1]];
        u16 type_id = READ_U16(2);
        u16 vtable = READ_U16(4);
        ValueResult res = allocTrait(vm, type_id, vtable, impl);
        if (res.code != RES_CODE_SUCCESS) {
            RETURN(res.code);
        }
        stack[pc[6]] = res.val;
        pc += 7;
        NEXT();
    }
    CASE(Box): {
        u16 type_id = READ_U16(2);
        stack[pc[4]] = zBox(vm, stack[pc[1]], type_id);
        pc += 5;
        NEXT();
    }
    CASE(Unbox): {
        u16 type_id = READ_U16(2);
        TypeId act_t = getTypeId(stack[pc[1]]);
        stack[pc[4]] = zUnbox(vm, stack[pc[1]], type_id);
        pc += 5;
        NEXT();
    }
    CASE(AddrLocal): {
        HeapObject* obj = VALUE_AS_HEAPOBJECT(stack[pc[1]]);
        bool lifted_struct = pc[2];
        if (lifted_struct) {
            HeapObject* inner = VALUE_AS_HEAPOBJECT(obj->object.firstValue);
            stack[pc[3]] = (u64)(&inner->object.firstValue);
        } else {
            stack[pc[3]] = (u64)(&obj->object.firstValue);
        }
        pc += 4;
        NEXT();
    }
    CASE(AddrConstIndex): {
        Value* ptr = (Value*)stack[pc[1]];
        stack[pc[3]] = (u64)(ptr + pc[2]);
        pc += 4;
        NEXT();
    }
    CASE(AddrIndex): {
        Value* ptr = (Value*)stack[pc[1]];
        ptr += BITCAST(i64, stack[pc[2]]);
        stack[pc[3]] = (u64)ptr;
        pc += 4;
        NEXT();
    }
    CASE(Deref): {
        Value* src = (Value*)stack[pc[1]];
        bool retain_v = pc[2];
        if (retain_v) {
            retain(vm, *src);
        }
        stack[pc[3]] = *src;
        pc += 4;
        NEXT();
    }
    CASE(DerefStruct): {
        Value* ptr = (Value*)stack[pc[1]];
        u16 type_id = READ_U16(2);
        u8 nfields = pc[4];

        ValueResult res;
        if (nfields <= 4) {
            res = allocObjectSmall(vm, type_id, ptr, nfields);
        } else {
            res = allocObject(vm, type_id, ptr, nfields);
        }
        if (res.code != RES_CODE_SUCCESS) {
            RETURN(res.code);
        }
        stack[pc[5]] = res.val;
        pc += 6;
        NEXT();
    }
    CASE(SetDeref): {
        Value* dst = (Value*)stack[pc[1]];
        *dst = stack[pc[2]];
        pc += 3;
        NEXT();
    }
    CASE(SetDerefStruct): {
        Value* dst = (Value*)stack[pc[1]];
        u8 nfields = pc[2];
        HeapObject* obj = VALUE_AS_HEAPOBJECT(stack[pc[3]]);
        Value* src = objectGetValuesPtr((Object*)obj);
        memcpy(dst, src, nfields * sizeof(Value));
        releaseObject(vm, obj);
        pc += 4;
        NEXT();
    }
    CASE(UnwrapChoice): {
        HeapObject* obj = VALUE_AS_HEAPOBJECT(stack[pc[1]]);
        Value* fields = objectGetValuesPtr(&obj->object);
        u8 tag = pc[2];
        if (VALUE_AS_INTEGER(fields[0]) == (_BitInt(48))pc[2]) {
            retain(vm, fields[pc[3]]);
            stack[pc[4]] = fields[pc[3]];
            pc += 5;
            NEXT();
        } else {
            panicUnexpectedChoice(vm, VALUE_AS_INTEGER(fields[0]), (_BitInt(48))pc[2]);
            RETURN(RES_CODE_PANIC);
        }
    }
    CASE(SetFieldDyn): {
        Value recv = stack[pc[1]];
        if (VALUE_IS_POINTER(recv)) {
            HeapObject* obj = VALUE_AS_HEAPOBJECT(recv);
            u16 fieldId = READ_U16(2);
            TypeField res = zGetTypeField(vm, OBJ_TYPEID(obj), fieldId);
            Value val = stack[pc[4]];
            if (res.offset != NULL_U16) {
                TypeId rightTypeId = getTypeId(val);
                if (res.type_id != TYPE_DYN) {
                    // Must perform type check on rhs.
                    if (!isTypeCompat(rightTypeId, res.type_id)) {
                        panicIncompatibleFieldType(vm, res.type_id, rightTypeId);
                        RETURN(RES_CODE_PANIC);
                    }
                }

                Value* lastValue = objectGetFieldPtr((Object*)obj, res.offset);
                if (res.boxed) {
                    release(vm, *lastValue);
                    *lastValue = val;
                } else {
                    *lastValue = zUnbox(vm, val, res.type_id);
                    release(vm, val);
                }

                pc[0] = CodeSetFieldDynIC;
                WRITE_U16(5, OBJ_TYPEID(obj));
                WRITE_U16(7, rightTypeId);
                pc[9] = (u8)res.offset;
            } else {
                SAVE_STATE();
                ResultCode code = zSetFieldFallback(vm, obj, fieldId, val);
                if (code != RES_CODE_SUCCESS) {
                    RESTORE_STATE();
                    RETURN(code);
                }
                release(vm, val);
            }
            pc += 10;
            NEXT();
        } else {
            // return vm.setFieldNotObjectError();
            RETURN(RES_CODE_UNKNOWN);
        }
    }
    CASE(SetFieldDynIC): {
        Value recv = stack[pc[1]];
        if (VALUE_IS_POINTER(recv)) {
            Value val = stack[pc[4]];
            HeapObject* obj = VALUE_AS_HEAPOBJECT(recv);
            if ((OBJ_TYPEID(obj) == READ_U16(5)) && (getTypeId(val) == READ_U16(7))) {
                Value* lastValue = objectGetFieldPtr((Object*)obj, pc[9]);
                release(vm, *lastValue);
                *lastValue = val;
                pc += 10;
                NEXT();
            } else {
                // Deoptimize.
                pc[0] = CodeSetFieldDyn;
                NEXT();
            }
        } else {
            // return vm.getFieldMissingSymbolError();
            RETURN(RES_CODE_UNKNOWN);
        }
    }
    CASE(SetField): {
        HeapObject* obj = VALUE_AS_HEAPOBJECT(stack[pc[1]]);
        Value* lastValue = objectGetFieldPtr((Object*)obj, pc[2]);
        release(vm, *lastValue);
        *lastValue = stack[pc[3]];
        pc += 4;
        NEXT();
    }
    CASE(Catch): {
        pc += READ_U16(1);
        NEXT();
    }
    CASE(Throw): {
        Value err = stack[pc[1]];
        if (VALUE_IS_ERROR(err)) {
            vm->c.curFiber->panicPayload = err;
            vm->c.curFiber->panicType = PANIC_NATIVE_THROW;
            RETURN(RES_CODE_PANIC);
        } else {
            panicStaticMsg(vm, "Not an error.");
            RETURN(RES_CODE_PANIC);
        }
    }
    CASE(Coinit): {
        u8 startArgsLocal = pc[1];
        u8 numArgs = pc[2];
        u8 argDst = pc[3];
        u8 jump = pc[4];
        u8 initialStackSize = pc[5];
        u8 dst = pc[6];

        ValueResult res = zAllocFiber(vm, pcOffset(vm, pc + INST_COINIT_LEN), stack + startArgsLocal, numArgs, argDst, initialStackSize);
        if (res.code != RES_CODE_SUCCESS) {
            RETURN(res.code);
        }
        stack[dst] = res.val;
        pc += jump;
        NEXT();
    }
    CASE(Coyield):
        if (vm->c.curFiber != &vm->c.mainFiber) {
            PcFpOff res = zPopFiber(vm, pcOffset(vm, pc), stack, VALUE_BOOLEAN(false));
            pc = vm->c.instPtr + res.pc;
            stack = vm->c.stackPtr + res.fp;
        } else {
            pc += 3;
        }
        NEXT();
    CASE(Coresume): {
        Value fiber = stack[pc[1]];
        if (VALUE_IS_POINTER(fiber)) {
            HeapObject* obj = VALUE_AS_HEAPOBJECT(fiber);
            if (OBJ_TYPEID(obj) == TYPE_FIBER) {
                if ((Fiber*)obj != vm->c.curFiber) {
                    if (obj->fiber.pcOffset != NULL_U32) {
                        PcFp res = zPushFiber(vm, pcOffset(vm, pc + 3), stack, (Fiber*)obj, pc[2]);
                        pc = res.pc;
                        stack = res.fp;
                        NEXT();
                    }
                }
            }
            releaseObject(vm, obj);
        }
        pc += 3;
        NEXT();
    }
    CASE(Coreturn): {
        bool box = pc[3];
        if (box) {
            TypeId ret_t = (TypeId)READ_U16(1);
            stack[1] = zBox(vm, stack[1], ret_t);
        }
        pc += 3;
        if (vm->c.curFiber != &vm->c.mainFiber) {
            PcFpOff res = zPopFiber(vm, NULL_U32, stack, stack[1]);
            pc = vm->c.instPtr + res.pc;
            stack = vm->c.stackPtr + res.fp;
        }
        NEXT();
    }
    CASE(Await): {
        Value mb_future = stack[pc[1]];
        pc += 2;
        vm->c.curPc = pc;
        vm->c.curStack = stack;
        ResultCode code = zAwait(vm, mb_future);
        if (code == RES_CODE_AWAIT) {
            RETURN(RES_CODE_AWAIT);
        }
        NEXT();
    }
    CASE(FutureValue): { 
        Value mb_future = stack[pc[1]];
        stack[pc[2]] = zFutureValue(vm, mb_future);
        pc += 3;
        NEXT();
    }
    CASE(Retain): {
        retain(vm, stack[pc[1]]);
        pc += 2;
        NEXT();
    }
    CASE(Up): {
        Value value = stack[pc[1]];
        ValueResult res = allocUpValue(vm, value);
        if (res.code != RES_CODE_SUCCESS) {
            RETURN(res.code);
        }
        stack[pc[2]] = res.val;
        pc += 3;
        NEXT();
    }
    CASE(SetUpValue): {
        Value up = stack[pc[1]];
        Value rval = stack[pc[2]];
        bool release_flag = pc[3];
#if TRACE
        ASSERT(VALUE_IS_POINTER(up));
#endif
        HeapObject* obj = VALUE_AS_HEAPOBJECT(up);
#if TRACE
        ASSERT(OBJ_TYPEID(obj) == TYPE_UPVALUE);
#endif
        if (release_flag) {
            release(vm, obj->up.val);
        }
        obj->up.val = rval;
        pc += 4;
        NEXT();
    }
    CASE(UpValue): {
        Value up = stack[pc[1]];
#if TRACE
        if (!VALUE_IS_UPVALUE(up)) {
            TRACEV("Expected box value.");
            zFatal();
        }
#endif
        stack[pc[2]] = VALUE_AS_HEAPOBJECT(up)->up.val;
        pc += 3;
        NEXT();
    }
    CASE(Captured): {
        Value closure = stack[pc[1]];
#if TRACE
        if (!VALUE_IS_CLOSURE(vm, closure)) {
            TRACEV("Expected closure value.");
            zFatal();
        }
#endif
        Value up = closureGetCapturedValuesPtr(&VALUE_AS_HEAPOBJECT(closure)->func_union)[pc[2]];
#if TRACE
        if (!VALUE_IS_UPVALUE(up)) {
            TRACEV("Expected box value.");
            zFatal();
        }
#endif
        Value val = VALUE_AS_HEAPOBJECT(up)->up.val;
        bool retain_flag = pc[3];
        if (retain_flag) {
            retain(vm, val);
        }
        stack[pc[4]] = val;
        pc += 5;
        NEXT();
    }
    CASE(SetCaptured): {
        Value closure = stack[pc[1]];
#if TRACE
        if (!VALUE_IS_CLOSURE(vm, closure)) {
            TRACEV("Expected closure value.");
            zFatal();
        }
#endif
        Value up = closureGetCapturedValuesPtr(&VALUE_AS_HEAPOBJECT(closure)->func_union)[pc[2]];
        HeapObject* obj = VALUE_AS_HEAPOBJECT(up);
#if TRACE
        ASSERT(OBJ_TYPEID(obj) == TYPE_UPVALUE);
#endif
        release(vm, obj->up.val);
        obj->up.val = stack[pc[3]];
        pc += 4;
        NEXT();
    }
    CASE(TagLit): {
        u8 sym = pc[1];
        stack[pc[2]] = VALUE_TAGLIT(sym);
        pc += 3;
        NEXT();
    }
    CASE(Enum): {
        u8 tagId = pc[1];
        u8 val = pc[2];
        stack[pc[3]] = VALUE_ENUM(tagId, val);
        pc += 4;
        NEXT();
    }
    CASE(Symbol): {
        u8 symId = pc[1];
        stack[pc[2]] = VALUE_SYMBOL(symId);
        pc += 3;
        NEXT();
    }
    CASE(Cast): {
        Value val = stack[pc[1]];
        u16 expTypeId = READ_U16(2);
        if (getTypeId(val) == expTypeId) {
            stack[pc[4]] = val;
            pc += 5;
            NEXT();
        } else {
            panicCastFail(vm, getTypeId(val), expTypeId);
            RETURN(RES_CODE_PANIC);
        }
    }
    CASE(CastAbstract): {
        Value val = stack[pc[1]];
        u16 expTypeId = READ_U16(2);
        if (expTypeId == TYPE_ANY) {
            stack[pc[4]] = val;
            pc += 5;
            NEXT();
        } else {
            panicCastFail(vm, getTypeId(val), expTypeId);
            RETURN(RES_CODE_PANIC);
        }
    }
    CASE(BitwiseAnd): {
        INTEGER_BINOP(stack[pc[3]] = BITCAST(u64, left & right))
    }
    CASE(BitwiseOr): {
        INTEGER_BINOP(stack[pc[3]] = BITCAST(u64, left | right))
    }
    CASE(BitwiseXor): {
        INTEGER_BINOP(stack[pc[3]] = BITCAST(u64, left ^ right))
    }
    CASE(BitwiseNot): {
        INTEGER_UNOP(stack[pc[2]] = BITCAST(u64, ~val))
    }
    CASE(BitwiseLeftShift): {
        INTEGER_BINOP(
            if (right > 63 || right < 0) {
                panicOutOfBounds(vm);
                RETURN(RES_CODE_PANIC);
            }
            stack[pc[3]] = BITCAST(u64, left << right);
        )
    }
    CASE(BitwiseRightShift): {
        INTEGER_BINOP(
            if (right > 64 || right < 0) {
                panicOutOfBounds(vm);
                RETURN(RES_CODE_PANIC);
            }
            stack[pc[3]] = BITCAST(u64, left >> right);
        )
    }
    CASE(AddInt): {
        INTEGER_BINOP(stack[pc[3]] = BITCAST(u64, left + right))
    }
    CASE(SubInt): {
        INTEGER_BINOP(stack[pc[3]] = BITCAST(u64, left - right))
    }
    CASE(MulInt): {
        INTEGER_BINOP(stack[pc[3]] = BITCAST(u64, left * right))
    }
    CASE(DivInt): {
        INTEGER_BINOP(
            if (right == 0) {
                panicDivisionByZero(vm);
                RETURN(RES_CODE_PANIC);
            }
            stack[pc[3]] = BITCAST(u64, left / right);
        )
    }
    CASE(PowInt): {
        INTEGER_BINOP(stack[pc[3]] = BITCAST(u64, ipow(left, right)))
    }
    CASE(ModInt): {
        INTEGER_BINOP(
            if (right == 0) {
                panicDivisionByZero(vm);
                RETURN(RES_CODE_PANIC);
            }
            stack[pc[3]] = BITCAST(u64, left % right);
        )
    }
    CASE(NegInt): {
        INTEGER_UNOP(stack[pc[2]] = BITCAST(u64, -val))
    }
    CASE(ForRangeInit): {
        i64 start = BITCAST(i64, stack[pc[1]]);
        i64 end = BITCAST(i64, stack[pc[2]]);
        bool increment = pc[3];

        stack[pc[4]] = start;
        stack[pc[5]] = start;
        u16 offset = READ_U16(6);
        if (increment) {
            if (start >= end) {
                pc += offset + 6;
                NEXT();
            }
            pc[offset] = CodeForRange;
        } else {
            if (start <= end) {
                pc += offset + 6;
                NEXT();
            }
            pc[offset] = CodeForRangeReverse;
        }
        pc += 8;
        NEXT();
    }
    CASE(ForRange): {
        i64 counter = BITCAST(i64, stack[pc[1]]) + 1;
        if (counter < BITCAST(i64, stack[pc[2]])) {
            stack[pc[1]] = counter;
            stack[pc[3]] = counter;
            pc -= READ_U16(4);
        } else {
            pc += 6;
        }
        NEXT();
    }
    CASE(ForRangeReverse): {
        i64 counter = BITCAST(i64, stack[pc[1]]) - 1;
        if (counter > BITCAST(i64, stack[pc[2]])) {
            stack[pc[1]] = counter;
            stack[pc[3]] = counter;
            pc -= READ_U16(4);
        } else {
            pc += 6;
        }
        NEXT();
    }
    CASE(Match): {
        pc += zOpMatch(pc, stack);
        NEXT();
    }
    CASE(FuncPtr): {
        u16 funcId = READ_U16(1);
        u16 ptr_t = READ_U16(3);
        ValueResult res = zAllocFuncPtr(vm, ptr_t, funcId);
        if (res.code != RES_CODE_SUCCESS) {
            RETURN(res.code);
        }
        stack[pc[5]] = res.val;
        pc += 6;
        NEXT();
    }
    CASE(FuncUnion): {
        Value val = stack[pc[1]];
        u16 union_t = READ_U16(2);
        if (getTypeId(val) == TYPE_FUNC) {
            panicStaticMsg(vm, "TODO");
            RETURN(RES_CODE_PANIC);
        } else {
            // FuncPtr type.
            ValueResult res = allocFuncUnion(vm, union_t, &VALUE_AS_HEAPOBJECT(val)->func_ptr);
            if (res.code != RES_CODE_SUCCESS) {
                RETURN(res.code);
            }
            release(vm, val);
            stack[pc[4]] = res.val;
        }
        pc += 5;
        NEXT();
    }
    CASE(FuncSym): {
        u16 sym_t = READ_U16(1);
        void* func_sym = (void*)READ_U48(3);

        ValueResult res = allocFuncSym(vm, sym_t, func_sym);
        if (res.code != RES_CODE_SUCCESS) {
            RETURN(res.code);
        }
        stack[pc[9]] = res.val;
        pc += 10;
        NEXT();
    }
    CASE(StaticVar): {
        u16 symId = READ_U16(1);
        Value sym = ((StaticVar*)vm->c.varSyms.buf)[symId].value;
        stack[pc[3]] = sym;
        pc += 4;
        NEXT();
    }
    CASE(SetStaticVar): {
        u16 symId = READ_U16(1);
        bool release_ = pc[4];
        if (release_) {
            Value prev = ((StaticVar*)vm->c.varSyms.buf)[symId].value;
            release(vm, prev);
        }
        ((StaticVar*)vm->c.varSyms.buf)[symId].value = stack[pc[3]];
        pc += 5;
        NEXT();
    }
    CASE(Context): {
        u8 idx = pc[1];
        Value val = ((ContextVar*)vm->c.context_vars.buf)[idx].value;
        retain(vm, val);
        stack[pc[2]] = val;
        pc += 3;
        NEXT();
    }
    CASE(Type): {
        u32 type_id = READ_U32(1);
        bool expr_type = pc[5];
        ValueResult res;
        if (expr_type) {
            res = allocExprType(vm, type_id);
        } else {
            res = allocType(vm, type_id);
        }
        if (LIKELY(res.code == RES_CODE_SUCCESS)) {
            stack[pc[6]] = res.val;
            pc += 7;
            NEXT();
        }
        RETURN(res.code);
    }
    CASE(End): {
        zEnd(vm, pc);
        RETURN(RES_CODE_SUCCESS);
    }
#if CGOTO
#else
    }
#endif
}