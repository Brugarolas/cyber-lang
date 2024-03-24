const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const stdx = @import("stdx");
const fatal = cy.fatal;
const cy = @import("../cyber.zig");
const c = @import("../capi.zig");
const Value = cy.Value;
const bindings = @import("bindings.zig");
const Symbol = bindings.Symbol;
const fmt = @import("../fmt.zig");
const rt = cy.rt;
const bt = cy.types.BuiltinTypes;
const vmc = cy.vmc;
const string = @import("string.zig");

const log = cy.log.scoped(.core);

pub const VmSrc = @embedFile("builtins_vm.cy");
pub const Src = @embedFile("builtins.cy");
pub fn funcLoader(_: ?*c.VM, func: c.FuncInfo, out_: [*c]c.FuncResult) callconv(.C) bool {
    const out: *c.FuncResult = out_;
    const name = c.fromStr(func.name);
    if (std.mem.eql(u8, funcs[func.idx].@"0", name)) {
        out.ptr = @ptrCast(@alignCast(funcs[func.idx].@"1"));
        return true;
    }
    return false;
}

const NameFunc = struct { []const u8, cy.ZHostFuncFn };
const funcs = [_]NameFunc{
    // Utils.
    .{"copy",           copy},
    .{"dump",           zErrFunc2(dump)},
    .{"errorReport",    zErrFunc2(errorReport)},
    .{"getObjectRc",    zErrFunc2(getObjectRc)},
    .{"is",             is},
    .{"isAlpha",        isAlpha},
    .{"isDigit",        isDigit},
    .{"isNone",         isNone},
    .{"must",           zErrFunc2(must)},
    .{"panic",          zErrFunc2(panic)},
    .{"parseCyber",     zErrFunc2(parseCyber)},
    .{"parseCyon",      zErrFunc2(parseCyon)},
    .{"performGC",      zErrFunc2(performGC)},
    .{"print",          print},
    .{"runestr",        zErrFunc2(runestr)},
    .{"toCyon",         zErrFunc2(toCyon)},
    .{"typeof",         typeof},
    .{"typesym",        cFunc(typesym)},

    // bool
    .{"bool.'$call'", boolCall},

    // error
    .{"sym", errorSym},
    .{"error.'$call'", errorCall},
    
    // int
    .{"$prefix~", bindings.intNot},
    .{"$prefix-", bindings.intNeg},
    // Inlined opcodes allow the right arg to be dynamic so the compiler can gen more of those.
    // So for now, the runtime signature reflects that.
    .{"$infix<", bindings.intLess},
    .{"$infix<=", bindings.intLessEq},
    .{"$infix>", bindings.intGreater},
    .{"$infix>=", bindings.intGreaterEq},
    .{"$infix+", bindings.intAdd},
    .{"$infix-", bindings.intSub},
    .{"$infix*", bindings.intMul},
    .{"$infix/", bindings.intDiv},
    .{"$infix%", bindings.intMod},
    .{"$infix^", bindings.intPow},
    .{"$infix&", bindings.intAnd},
    .{"$infix|", bindings.intOr},
    .{"$infix||", bindings.intXor},
    .{"$infix<<", bindings.intLeftShift},
    .{"$infix>>", bindings.intRightShift},
    .{"fmt", zErrFunc2(intFmt)},
    .{"fmt", zErrFunc2(intFmt2)},
    .{"int.'$call'", intCall},

    // float
    .{"$prefix-", bindings.floatNeg},
    .{"$infix<", bindings.floatLess},
    .{"$infix<=", bindings.floatLessEq},
    .{"$infix>", bindings.floatGreater},
    .{"$infix>=", bindings.floatGreaterEq},
    .{"$infix+", bindings.floatAdd},
    .{"$infix-", bindings.floatSub},
    .{"$infix*", bindings.floatMul},
    .{"$infix/", bindings.floatDiv},
    .{"$infix%", bindings.floatMod},
    .{"$infix^", bindings.floatPow},
    .{"float.'$call'", floatCall},

    // List
    .{"$index",     bindings.listIndex},
    .{"$index",     zErrFunc2(bindings.listSlice)},
    .{"$setIndex",  bindings.listSetIndex},
    .{"append",     zErrFunc2(bindings.listAppendList)},
    .{"append",     zErrFunc2(bindings.listAppend)},
    .{"insert",     bindings.listInsert},
    .{"iterator",   bindings.listIterator},
    .{"join",       zErrFunc2(bindings.listJoin)},
    .{"len",        bindings.listLen},
    .{"remove",     bindings.listRemove},
    .{"resize",     bindings.listResize},
    // .{"sort", bindings.listSort, .standard},
    .{"List.fill",  listFill},

    // ListIterator
    .{"next", bindings.listIteratorNext},

    // Tuple
    .{"$index", bindings.tupleIndex},

    // Map
    .{"$index", bindings.mapIndex},
    .{"$setIndex", zErrFunc2(bindings.mapSetIndex)},
    .{"contains", bindings.mapContains},
    .{"get", bindings.mapGet},
    .{"remove", bindings.mapRemove},
    .{"size", bindings.mapSize},
    .{"iterator", bindings.mapIterator},

    // MapIterator
    .{"next", bindings.mapIteratorNext},

    // String
    .{"$infix+", string.concat},
    .{"concat", string.concat},
    .{"count", string.count},
    .{"endsWith", string.endsWith},
    .{"find", string.find},
    .{"findAnyRune", string.findAnyRune},
    .{"findRune", string.findRune},
    .{"insert", zErrFunc2(string.insertFn)},
    .{"isAscii", string.isAscii},
    .{"len", string.lenFn},
    .{"less", string.less},
    .{"lower", string.lower},
    .{"replace", string.stringReplace},
    .{"repeat", string.repeat},
    .{"seek", zErrFunc2(string.seek)},
    .{"sliceAt", zErrFunc2(string.sliceAt)},
    .{"$index", zErrFunc2(string.runeAt)},
    .{"$index", string.sliceFn},
    .{"split", zErrFunc2(string.split)},
    .{"startsWith", string.startsWith},
    .{"trim", string.trim},
    .{"upper", string.upper},
    .{"String.'$call'", zErrFunc2(string.stringCall)},

    // Array
    .{"$infix+",        arrayConcat},
    .{"concat",         arrayConcat},
    .{"decode",         arrayDecode},
    .{"decode",         arrayDecode1},
    .{"endsWith",       arrayEndsWith},
    .{"find",           arrayFind},
    .{"findAnyByte",    arrayFindAnyByte},
    .{"findByte",       arrayFindByte},
    .{"fmt",            zErrFunc2(arrayFmt)},
    .{"getByte",        zErrFunc2(arrayGetByte)},
    .{"getInt",         zErrFunc2(arrayGetInt)},
    .{"getInt32",       zErrFunc2(arrayGetInt32)},
    .{"insert",         arrayInsert},
    .{"insertByte",     arrayInsertByte},
    .{"len",            arrayLen},
    .{"repeat",         zErrFunc2(arrayRepeat)},
    .{"replace",        arrayReplace},
    .{"$index",         zErrFunc2(arrayGetByte)},
    .{"$index",         arraySlice},
    .{"split",          zErrFunc2(arraySplit)},
    .{"startsWith",     arrayStartsWith},
    .{"trim",           zErrFunc2(arrayTrim)},
    .{"Array.'$call'",  zErrFunc2(arrayCall)},

    // pointer
    .{"addr", pointerAddr},
    .{"asObject", pointerAsObject},
    .{"fromCstr", zErrFunc2(pointerFromCstr)},
    .{"get", zErrFunc2(pointerGet)},
    .{"set", zErrFunc2(pointerSet)},
    .{"toArray", zErrFunc2(pointerToArray)},
    .{"pointer.'$call'", pointerCall},

    // ExternFunc
    .{"addr", externFuncAddr},

    // Fiber
    .{"status", fiberStatus},

    // metatype
    .{"id", metatypeId},
};

const NameType = struct { []const u8, cy.TypeId };
const types = [_]NameType{
    .{"bool", bt.Boolean },
    .{"error", bt.Error },
    .{"int", bt.Integer },
    .{"float", bt.Float }, 
    .{"List", bt.List },
    .{"ListIterator", bt.ListIter },
    .{"Tuple", bt.Tuple },
    .{"Map", bt.Map },
    .{"MapIterator", bt.MapIter },
    .{"String", bt.String },
    .{"Array", bt.Array },
    .{"pointer", bt.Pointer },
    .{"ExternFunc", bt.ExternFunc },
    .{"Fiber", bt.Fiber },
    .{"metatype", bt.MetaType },
};

pub fn typeLoader(_: ?*c.VM, info: c.TypeInfo, out_: [*c]c.TypeResult) callconv(.C) bool {
    const out: *c.TypeResult = out_;
    const name = c.fromStr(info.name);
    if (std.mem.eql(u8, types[info.idx].@"0", name)) {
        out.type = c.BindTypeDecl;
        out.data.decl = .{
            .type_id = types[info.idx].@"1",
        };
        return true;
    }
    return false;
}

const CustomType = bool;
const NameType2 = struct { []const u8, cy.TypeId, CustomType };
const vm_types = [_]NameType2{
    .{"void", bt.Void, true },
    .{"bool", bt.Boolean, false },
    .{"symbol", bt.Symbol, false },
    .{"error", bt.Error, false },
    .{"int", bt.Integer, false },
    .{"float", bt.Float, false }, 
    .{"placeholder1", bt.Placeholder1, true }, 
    .{"placeholder2", bt.Placeholder2, true }, 
    .{"placeholder3", bt.Placeholder3, true }, 
    .{"dynamic", bt.Dynamic, true },
    .{"any", bt.Any, true },
    .{"type", bt.Type, true },
    .{"List", bt.List, true },
    .{"ListIterator", bt.ListIter, true },
    .{"Tuple", bt.Tuple, true },
    .{"Map", bt.Map, true },
    .{"MapIterator", bt.MapIter, true },
    .{"String", bt.String, true },
    .{"Array", bt.Array, true },
    .{"pointer", bt.Pointer, true },
    .{"Closure", bt.Closure, true },
    .{"Lambda", bt.Lambda, true },
    .{"HostFunc", bt.HostFunc, true },
    .{"ExternFunc", bt.ExternFunc, true },
    .{"Fiber", bt.Fiber, true },
    .{"metatype", bt.MetaType, true },
    .{"Range", bt.Range, true },
    .{"Box", bt.Box, true },
    .{"TccState", bt.TccState, true },
};

pub fn vmTypeLoader(_: ?*c.VM, info: c.TypeInfo, out_: [*c]c.TypeResult) callconv(.C) bool {
    const out: *c.TypeResult = out_;
    const name = c.fromStr(info.name);
    if (std.mem.eql(u8, vm_types[info.idx].@"0", name)) {
        if (vm_types[info.idx].@"2") {
            out.type = c.BindTypeCustom;
            out.data.custom = .{
                .out_type_id = null,
                .type_id = vm_types[info.idx].@"1",
                .get_children = null,
                .finalizer = null,
            };
        } else {
            out.type = c.BindTypeDecl;
            out.data.decl = .{
                .type_id = vm_types[info.idx].@"1",
            };
        }
        return true;
    }
    return false;
}

pub var OptionInt: cy.TypeId = undefined;
pub var OptionAny: cy.TypeId = undefined;
pub var OptionTuple: cy.TypeId = undefined;
pub var OptionMap: cy.TypeId = undefined;
pub var OptionArray: cy.TypeId = undefined;
pub var OptionString: cy.TypeId = undefined;

pub fn onLoad(vm_: ?*c.VM, mod: c.Sym) callconv(.C) void {
    const vm: *cy.VM = @ptrCast(@alignCast(vm_));
    const chunk_sym = cy.Sym.fromC(mod).cast(.chunk);
    const b = bindings.ModuleBuilder.init(vm.compiler, @ptrCast(chunk_sym));
    if (cy.Trace) {
        b.declareFuncSig("traceRetains", &.{}, bt.Integer, traceRetains) catch cy.fatal();
        b.declareFuncSig("traceReleases", &.{}, bt.Integer, traceRetains) catch cy.fatal();
    }

    const option_tmpl = chunk_sym.getMod().getSym("Option").?.toC();

    const int_t = c.newType(vm_, bt.Integer);
    defer c.release(vm_, int_t);
    OptionInt = c.expandTypeTemplate(option_tmpl, @constCast(&[_]c.Value{ int_t }), 1);

    const any_t = c.newType(vm_, bt.Any);
    defer c.release(vm_, any_t);
    OptionAny = c.expandTypeTemplate(option_tmpl, @constCast(&[_]c.Value{ any_t }), 1);

    const tuple_t = c.newType(vm_, bt.Tuple);
    defer c.release(vm_, tuple_t);
    OptionTuple = c.expandTypeTemplate(option_tmpl, @constCast(&[_]c.Value{ tuple_t }), 1);

    const map_t = c.newType(vm_, bt.Map);
    defer c.release(vm_, map_t);
    OptionMap = c.expandTypeTemplate(option_tmpl, @constCast(&[_]c.Value{ map_t }), 1);

    const array_t = c.newType(vm_, bt.Array);
    defer c.release(vm_, array_t);
    OptionArray = c.expandTypeTemplate(option_tmpl, @constCast(&[_]c.Value{ array_t }), 1);

    const string_t = c.newType(vm_, bt.String);
    defer c.release(vm_, string_t);
    OptionString = c.expandTypeTemplate(option_tmpl, @constCast(&[_]c.Value{ string_t }), 1);

    // Verify all core types have been initialized.
    if (cy.Trace) {
        for (0..cy.types.BuiltinEnd) |i| {
            const type_e = vm.sema.types.items[i];
            if (type_e.kind == .null) {
                cy.panicFmt("Type {} is uninited.", .{i});
            }
        }
    }
}

pub fn cFunc(func: *const fn (vm: cy.Context, args: [*]const Value, nargs: u8) callconv(.C) Value) cy.ZHostFuncFn {
    return @ptrCast(func);
}

pub fn zErrFunc2(comptime func: fn (vm: *cy.VM, args: [*]const Value, nargs: u8) anyerror!Value) cy.ZHostFuncFn {
    const S = struct {
        pub fn genFunc(vm: *cy.VM, args: [*]const Value, nargs: u8) callconv(.C) Value {
            return @call(.always_inline, func, .{vm, args, nargs}) catch |err| {
                return @call(.never_inline, prepThrowZError, .{vm, err, @errorReturnTrace()});
            };
        }
    };
    return @ptrCast(&S.genFunc);
}

pub fn zErrFunc(comptime func: fn (vm: *cy.UserVM, args: [*]const Value, nargs: u8) anyerror!Value) cy.ZHostFuncFn {
    const S = struct {
        pub fn genFunc(vm: *cy.VM, args: [*]const Value, nargs: u8) Value {
            return @call(.always_inline, func, .{@as(*cy.UserVM, @ptrCast(vm)), args, nargs}) catch |err| {
                return @call(.never_inline, prepThrowZError, .{vm, err, @errorReturnTrace()});
            };
        }
    };
    return S.genFunc;
}

pub fn prepThrowZError(ctx: cy.Context, err: anyerror, optTrace: ?*std.builtin.StackTrace) Value {
    if (!cy.isFreestanding and c.verbose()) {
        if (optTrace) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
    }
    const sym = errorSymbol(err);
    return rt.prepThrowError(ctx, sym);
}

pub fn prepThrowZError2(ctx: cy.Context, err: anyerror, optTrace: ?*std.builtin.StackTrace) rt.Error {
    if (!cy.isFreestanding and c.verbose()) {
        if (optTrace) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
    }
    const sym = errorSymbol(err);
    _ = rt.prepThrowError(ctx, sym);
    return rt.Error.init(@tagName(sym));
}

fn errorSymbol(err: anyerror) Symbol {
    switch (err) {
        error.AssertError           => return .AssertError,
        error.Unicode               => return .Unicode,
        error.InvalidArgument       => return .InvalidArgument,
        error.InvalidEnumTag        => return .InvalidArgument,
        error.FileNotFound          => return .FileNotFound,
        error.OutOfBounds           => return .OutOfBounds,
        error.PermissionDenied      => return .PermissionDenied,
        error.StdoutStreamTooLong   => return .StreamTooLong,
        error.StderrStreamTooLong   => return .StreamTooLong,
        error.EndOfStream           => return .EndOfStream,
        else                        => return .UnknownError,
    }
}

fn traceRetains(vm: *cy.VM, _: [*]const Value, _: u8) Value {
    return Value.initInt(vm.trace.numRetains);
}

fn traceReleases(vm: *cy.VM, _: [*]const Value, _: u8) Value {
    return Value.initInt(vm.trace.numReleases);
}

pub fn listFill(vm: *cy.VM, args: [*]const Value, _: u8) Value {
    return vm.allocListFill(args[0], @intCast(args[1].asInteger())) catch cy.fatal();
}

pub fn copy(vm: *cy.VM, args: [*]const Value, _: u8) Value {
    const val = args[0];
    return cy.value.shallowCopy(vm, val);
}

pub fn errorReport(vm: *cy.VM, _: [*]const Value, _: u8) anyerror!Value {
    const curFrameLen = vm.compactTrace.len;

    // Append frames from current call-site.
    try cy.fiber.recordCurFrames(vm);

    // Remove top frame since it contains the `errorReport` call.
    if (vm.compactTrace.len > curFrameLen) {
        vm.compactTrace.remove(curFrameLen);
    }

    const trace = try cy.debug.allocStackTrace(vm, vm.stack, vm.compactTrace.items());
    defer vm.alloc.free(trace);

    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(vm.alloc);

    const w = buf.writer(vm.alloc);
    try cy.debug.writeStackFrames(vm, w, trace);

    return vm.allocString(buf.items);
}

pub fn must(vm: *cy.VM, args: [*]const Value, nargs: u8) anyerror!Value {
    if (!args[0].isError()) {
        return args[0];
    } else {
        return panic(vm, args, nargs);
    }
}

pub fn panic(vm: *cy.VM, args: [*]const Value, _: u8) anyerror!Value {
    const str = try vm.getOrBufPrintValueStr(&cy.tempBuf, args[0]);
    return vm.prepPanic(str);
}

pub fn is(_: *cy.VM, args: [*]const Value, _: u8) Value {
    return Value.initBool(args[0].val == args[1].val);
}

pub fn isAlpha(vm: *cy.VM, args: [*]const Value, _: u8) Value {
    const num = args[0].asInteger();
    if (num < 0 or num >= 2 << 21) {
        return rt.prepThrowError(vm, .InvalidRune);
    }
    if (num > 255) {
        return Value.False;
    } else {
        return Value.initBool(std.ascii.isAlphabetic(@intCast(num)));
    }
}

pub fn isDigit(vm: *cy.VM, args: [*]const Value, _: u8) Value {
    const num = args[0].asInteger();
    if (num < 0 or num >= 2 << 21) {
        return rt.prepThrowError(vm, .InvalidRune);
    }
    if (num > 255) {
        return Value.False;
    } else {
        return Value.initBool(std.ascii.isDigit(@intCast(num)));
    }
}

pub fn isNone(vm: *cy.VM, args: [*]const Value, _: u8) Value {
    const type_e = vm.types[args[0].getTypeId()];
    if (type_e.kind != .option) {
        return Value.False;
    }
    const is_none = args[0].asHeapObject().object.getValue(0).asInteger() == 0;
    return Value.initBool(is_none);
}

pub fn runestr(vm: *cy.VM, args: [*]const Value, _: u8) anyerror!Value {
    const num = args[0].asInteger();
    if (num < 0 or num >= 2 << 21) {
        return rt.prepThrowError(vm, .InvalidRune);
    }
    const rune: u21 = @intCast(num);
    if (std.unicode.utf8ValidCodepoint(rune)) {
        var buf: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(rune, &buf);
        return vm.allocString(buf[0..len]);
    } else {
        return rt.prepThrowError(vm, .InvalidRune);
    }
}

pub fn dump(vm: *cy.VM, args: [*]const Value, _: u8) anyerror!Value {
    const res = try allocToCyon(vm, vm.alloc, args[0]);
    defer vm.alloc.free(res);
    rt.print(vm, res);
    rt.print(vm, "\n");
    return Value.Void;
}

pub fn getObjectRc(_: *cy.VM, args: [*]const Value, _: u8) anyerror!Value {
    if (args[0].isPointer()) {
        return Value.initInt(@intCast(args[0].asHeapObject().head.rc));
    } else {
        return Value.initInt(-1);
    }
}

pub fn toCyon(vm: *cy.VM, args: [*]const Value, _: u8) anyerror!Value {
    const res = try allocToCyon(vm, vm.alloc, args[0]);
    defer vm.alloc.free(res);
    return vm.allocString(res);
}

fn allocToCyon(vm: *cy.VM, alloc: std.mem.Allocator, root: Value) ![]const u8 {
    const S = struct {
        fn encodeMap(ctx: *cy.EncodeMapContext, val: cy.Value) anyerror!void {
            const uservm = cy.ptrAlignCast(*cy.VM, ctx.user_ctx);
            var iter = val.asHeapObject().map.map().iterator();
            while (iter.next()) |e| {
                const key = try uservm.getOrBufPrintValueStr(&cy.tempBuf, e.key);
                switch (e.value.getUserTag()) {
                    .float => {
                        try ctx.encodeFloat(key, e.value.asF64());
                    },
                    .int => {
                        try ctx.encodeInt(key, e.value.asInteger());
                    },
                    .string => {
                        const keyDupe = try uservm.alloc.dupe(u8, key);
                        defer uservm.alloc.free(keyDupe);
                        const str = try uservm.getOrBufPrintValueStr(&cy.tempBuf, e.value);
                        try ctx.encodeString(keyDupe, str);
                    },
                    .bool => {
                        try ctx.encodeBool(key, e.value.asBool());
                    },
                    .map => {
                        try ctx.encodeMap(key, e.value, encodeMap);
                    },
                    .list => {
                        try ctx.encodeList(key, e.value, encodeList);
                    },
                    else => {},
                }
            }
        }
        fn encodeList(ctx: *cy.EncodeListContext, val: cy.Value) anyerror!void {
            const items = val.asHeapObject().list.items();
            for (items) |it| {
                try ctx.indent();
                switch (it.getUserTag()) {
                    .float => {
                        try ctx.encodeFloat(it.asF64());
                        _ = try ctx.writer.write(",\n");
                    },
                    .int => {
                        try ctx.encodeInt(it.asInteger());
                        _ = try ctx.writer.write(",\n");
                    },
                    .string => {
                        const uservm = cy.ptrAlignCast(*cy.VM, ctx.user_ctx);
                        const str = try uservm.getOrBufPrintValueStr(&cy.tempBuf, it);
                        try ctx.encodeString(str);
                        _ = try ctx.writer.write(",\n");
                    },
                    .bool => {
                        try ctx.encodeBool(it.asBool());
                        _ = try ctx.writer.write(",\n");
                    },
                    .map => {
                        try ctx.encodeMap(it, encodeMap);
                        _ = try ctx.writer.write(",\n");
                    },
                    .list => {
                        try ctx.encodeList(it, encodeList);
                        _ = try ctx.writer.write(",\n");
                    },
                    else => {},
                }
            }
        }
        fn encodeRoot(ctx: *cy.EncodeValueContext, val: anytype) !void {
            const T = @TypeOf(val);
            if (T == Value) {
                switch (val.getUserTag()) {
                    .float => {
                        try ctx.encodeFloat(val.asF64());
                    },
                    .int => {
                        try ctx.encodeInt(val.asInteger());
                    },
                    .string => {
                        const uservm = cy.ptrAlignCast(*cy.VM, ctx.user_ctx);
                        const str = try uservm.getOrBufPrintValueStr(&cy.tempBuf, val);
                        try ctx.encodeString(str);
                    },
                    .bool => {
                        try ctx.encodeBool(val.asBool());
                    },
                    .list => {
                        if (val.asHeapObject().list.items().len == 0) {
                            _ = try ctx.writer.write("[]");
                        } else {
                            try ctx.encodeList(val, encodeList);
                        }
                    },
                    .map => {
                        if (val.asHeapObject().map.inner.size == 0) {
                            _ = try ctx.writer.write("{}");
                        } else {
                            try ctx.encodeMap(val, encodeMap);
                        }
                    },
                    else => {},
                }
            } else {
                cy.panicFmt("unsupported: {s}", .{@typeName(T)});
            }
        }
    };
    return try cy.encodeCyon(alloc, vm, root, S.encodeRoot);
}

pub fn parseCyber(vm: *cy.VM, args: [*]const Value, _: u8) anyerror!Value {
    const src = args[0].asString();

    var parser = try cy.Parser.init(vm.alloc);
    defer parser.deinit();
    _ = try parser.parse(src, .{ .parseComments = true });

    return parseCyberGenResult(vm, &parser);
}

const ParseCyberState = struct {
    comments: []const cy.IndexSlice(u32),
    sb: std.ArrayListUnmanaged(u8),
    commentIdx: u32,
    pos: u32,
    node: cy.Node,
};

fn genTypeSpecString(vm: *cy.VM, ast: cy.ast.AstView, exprId: cy.NodeId) !cy.Value {
    if (exprId != cy.NullNode) {
        var sb: std.ArrayListUnmanaged(u8) = .{};
        defer sb.deinit(vm.alloc);

        var enc = cy.ast.Encoder{ .ast = ast };
        try enc.write(sb.writer(vm.alloc), exprId);

        return try vm.retainOrAllocAstring(sb.items);
    } else {
        return try vm.retainOrAllocAstring("");
    }
}

fn genNodeValue(vm: *cy.VM, ast: cy.ast.AstView, nodeId: cy.NodeId) !cy.Value {
    const node = ast.node(nodeId);
    const res = try vm.allocEmptyMap();
    const map = res.castHeapObject(*cy.heap.Map);
    switch (node.type()) {
        .funcHeader => {
            const name = ast.getNamePathInfoById(node.data.funcHeader.name).namePath;
            try vm.mapSet(map, try vm.retainOrAllocAstring("name"), try vm.allocString(name));

            const params = try vm.allocEmptyList();
            var paramId = node.data.funcHeader.paramHead;
            while (paramId != cy.NullNode) {
                const param = try genNodeValue(vm, ast, paramId);
                try params.asHeapObject().list.append(vm.alloc, param);
                paramId = ast.node(paramId).next();
            }
            try vm.mapSet(map, try vm.retainOrAllocAstring("params"), params);

            const ret = try genTypeSpecString(vm, ast, node.funcHeader_ret());
            try vm.mapSet(map, try vm.retainOrAllocAstring("ret"), ret);
        },
        .funcParam => {
            var name = ast.nodeStringById(node.data.funcParam.name);
            try vm.mapSet(map, try vm.retainOrAllocAstring("name"), try vm.allocString(name));

            const typeSpec = try genTypeSpecString(vm, ast, node.data.funcParam.typeSpec);
            try vm.mapSet(map, try vm.retainOrAllocAstring("typeSpec"), typeSpec);
        },
        else => {},
    }
    return res;
}

fn genDeclEntry(vm: *cy.VM, ast: cy.ast.AstView, decl: cy.parser.StaticDecl, state: *ParseCyberState) !Value {
    const entryv = try vm.allocEmptyMap();
    const entry = entryv.castHeapObject(*cy.heap.Map);
    try vm.mapSet(entry, try vm.retainOrAllocAstring("type"), try vm.retainOrAllocAstring(@tagName(decl.declT)));
    var name: []const u8 = undefined;
    const node = ast.node(decl.nodeId);
    switch (decl.declT) {
        .typeTemplate => {
            const typeDecl = ast.node(node.data.typeTemplate.typeDecl);
            switch (typeDecl.type()) {
                .objectDecl => {
                    const header = ast.node(typeDecl.data.objectDecl.header);
                    name = ast.nodeStringById(header.data.objectHeader.name);
                },
                .enumDecl => {
                    name = ast.nodeStringById(typeDecl.data.enumDecl.name);
                },
                else => {
                    return error.Unsupported;
                },
            }
        },
        .variable => {
            const varSpec = ast.node(node.data.staticDecl.varSpec);
            name = ast.getNamePathInfoById(varSpec.data.varSpec.name).namePath;

            const typeSpec = try genTypeSpecString(vm, ast, varSpec.data.varSpec.typeSpec);
            try vm.mapSet(entry, try vm.retainOrAllocAstring("typeSpec"), typeSpec);
        },
        .distinct_t => {
            const header = ast.node(node.data.distinct_decl.header);
            name = ast.nodeStringById(header.data.distinct_header.name);
        },
        .typeAlias => {
            name = ast.nodeStringById(node.data.typeAliasDecl.name);
        },
        .implicit_method => {
            const header = ast.node(node.data.func.header);
            name = ast.getNamePathInfoById(header.data.funcHeader.name).namePath;
            
            const headerv = try genNodeValue(vm, ast, node.data.func.header);
            try vm.mapSet(entry, try vm.retainOrAllocAstring("header"), headerv);
        },
        .func => {
            const header = ast.node(node.data.func.header);
            name = ast.getNamePathInfoById(header.data.funcHeader.name).namePath;
        },
        .funcInit => {
            const header = ast.node(node.data.func.header);
            name = ast.getNamePathInfoById(header.data.funcHeader.name).namePath;

            const headerv = try genNodeValue(vm, ast, node.data.func.header);
            try vm.mapSet(entry, try vm.retainOrAllocAstring("header"), headerv);
        },
        .import => {
            name = ast.nodeStringById(node.data.importStmt.name);
        },
        .dynobject_t,
        .struct_t,
        .object => {
            const header = ast.node(node.data.objectDecl.header);
            name = ast.nodeStringById(header.data.objectHeader.name);
        },
        .enum_t => {
            name = ast.nodeStringById(node.data.enumDecl.name);
        },
    }
    state.pos = node.srcPos;
    state.node = node;

    // Find doc comments.
    if (try genDocComment(vm, ast, decl, state)) |docStr| {
        try vm.mapSet(entry, try vm.retainOrAllocAstring("docs"), docStr);
    }

    try vm.mapSet(entry, try vm.retainOrAllocAstring("name"), try vm.retainOrAllocAstring(name));
    try vm.mapSet(entry, try vm.retainOrAllocAstring("pos"), Value.initInt(@intCast(node.srcPos)));
    return entryv;
}

fn genDocComment(vm: *cy.VM, ast: cy.ast.AstView, decl: cy.parser.StaticDecl, state: *ParseCyberState) !?cy.Value {
    const comments = state.comments;
    if (state.commentIdx < comments.len) {
        var docStartIdx = state.commentIdx;
        var docEndIdx = state.commentIdx;
        while (state.commentIdx < comments.len) {
            var commentPos = comments[state.commentIdx];
            if (commentPos.start > state.pos) {
                break;
            }
            state.commentIdx += 1;
            docEndIdx = state.commentIdx;
            if (commentPos.len() < 3 or !std.mem.eql(u8, "--|", ast.src[commentPos.start..commentPos.start+3])) {
                // Not a doc comment, reset.
                docStartIdx = state.commentIdx;
                continue;
            }
            // Check it is connected to last comment.
            if (docEndIdx > docStartIdx + 1) {
                const last = comments[docEndIdx - 2];
                if (!ast.isAdjacentLine(last.end, commentPos.start)) {
                    // Reset.
                    docStartIdx = state.commentIdx;
                    continue;
                }
            }
        }
        if (docEndIdx > docStartIdx) {
            // Check it is connected to last comment.
            const last = comments[docEndIdx - 1];

            var posWithModifiers = state.pos;
            switch (decl.declT) {
                .variable => {
                    const varSpec = ast.node(state.node.data.staticDecl.varSpec);
                    if (varSpec.head.data.varSpec.modHead != cy.NullNode) {
                        const modifier = ast.node(varSpec.head.data.varSpec.modHead);
                        posWithModifiers = modifier.srcPos - 1;
                    }
                },
                .implicit_method,
                .funcInit,
                .func => {
                    const header = ast.node(state.node.data.func.header);
                    if (header.funcHeader_modHead() != cy.NullNode) {
                        const modifier = ast.node(header.funcHeader_modHead());
                        posWithModifiers = modifier.srcPos - 1;
                    }
                },
                .object => {
                    const header = ast.node(state.node.data.objectDecl.header);
                    if (header.head.data.objectHeader.modHead != cy.NullNode) {
                        const modifier = ast.node(header.head.data.objectHeader.modHead);
                        posWithModifiers = modifier.srcPos - 1;
                    }
                },
                else => {},
            }

            if (ast.isAdjacentLine(last.end, posWithModifiers)) {
                for (comments[docStartIdx..docEndIdx]) |docPos| {
                    try state.sb.appendSlice(vm.alloc, ast.src[docPos.start+3..docPos.end]);
                    try state.sb.append(vm.alloc, ' ');
                }
                const finalStr = std.mem.trim(u8, state.sb.items, " ");
                defer state.sb.clearRetainingCapacity();
                return try vm.allocString(finalStr);
            }
        }
    }
    return null;
}

fn parseCyberGenResult(vm: *cy.VM, parser: *const cy.Parser) !Value {
    const root = try vm.allocEmptyMap();
    errdefer vm.release(root);

    const map = root.asHeapObject().map.map();

    const decls = try vm.allocEmptyList();
    errdefer vm.release(decls);

    const declsList = decls.asHeapObject().list.getList();

    var state = ParseCyberState{
        .comments = parser.ast.comments.items,
        .commentIdx = 0,
        .sb = .{},
        .pos = undefined,
        .node = undefined,
    };
    defer state.sb.deinit(vm.alloc);

    const ast = parser.ast.view();

    for (parser.staticDecls.items) |decl| {
        const entry = try genDeclEntry(vm, ast, decl, &state);
        try declsList.append(vm.alloc, entry);
    }
    try map.put(vm.alloc, try vm.retainOrAllocAstring("decls"), decls);

    return root;
}

pub fn parseCyon(vm: *cy.VM, args: [*]const Value, _: u8) anyerror!Value {
    const src = args[0].asString();

    var parser = try cy.Parser.init(vm.alloc);
    defer parser.deinit();
    const val = try cy.decodeCyon(vm.alloc, &parser, src);
    return fromCyonValue(vm, val);
}

fn fromCyonValue(vm: *cy.VM, val: cy.DecodeValueIR) !Value {
    switch (val.getValueType()) {
        .list => {
            var dlist = try val.getList();
            defer dlist.deinit();
            const elems = try vm.alloc.alloc(Value, dlist.arr.len);
            for (elems, 0..) |*elem, i| {
                elem.* = try fromCyonValue(vm, dlist.getIndex(i));
            }
            return try cy.heap.allocOwnedList(vm, elems);
        },
        .map => {
            var dmap = try val.getMap();
            defer dmap.deinit();
            var iter = dmap.iterator();

            const mapVal = try vm.allocEmptyMap();
            const map = mapVal.asHeapObject();
            while (iter.next()) |entry| {
                const child = try fromCyonValue(vm, dmap.getValue(entry.key_ptr.*));
                const key = try vm.allocString(entry.key_ptr.*);
                stdMapPut(vm, map, key, child);
            }
            return mapVal;
        },
        .string => {
            const str = try val.allocString();
            defer val.alloc.free(str);
            // TODO: Use allocOwnedString
            return try vm.allocString(str);
        },
        .integer => {
            return Value.initInt(try val.getInt());
        },
        .float => {
            return Value.initF64(try val.getF64());
        },
        .bool => {
            return Value.initBool(val.getBool());
        },
    }
}

fn stdMapPut(vm: *cy.VM, obj: *cy.HeapObject, key: Value, value: Value) void {
    const map = cy.ptrAlignCast(*cy.MapInner, &obj.map.inner); 
    map.put(vm.alloc, key, value) catch cy.fatal();
}

pub fn performGC(vm: *cy.VM, _: [*]const Value, _: u8) anyerror!Value {
    const res = try cy.arc.performGC(vm);
    const map = try vm.allocEmptyMap();
    const cycKey = try vm.retainOrAllocAstring("numCycFreed");
    const objKey = try vm.retainOrAllocAstring("numObjFreed");
    defer {
        vm.release(cycKey);
        vm.release(objKey);
    }
    try map.asHeapObject().map.set(vm, cycKey, Value.initInt(@intCast(res.numCycFreed)));
    try map.asHeapObject().map.set(vm, objKey, Value.initInt(@intCast(res.numObjFreed)));
    return map;
}

pub fn print(vm: *cy.VM, args: [*]const cy.Value, _: u8) Value {
    const err = print_c(vm, args[0]);
    if (!err.isNull()) {
        return Value.Interrupt;
    }
    return Value.Void;
}

pub fn print_c(ctx: cy.Context, arg: rt.Any) callconv(.C) rt.Error {
    if (build_options.rt == .vm) {
        const str = ctx.getOrBufPrintValueStr(&cy.tempBuf, arg) catch |err| {
            return cy.builtins.prepThrowZError2(ctx, err, @errorReturnTrace());
        };
        rt.print(ctx, str);
        rt.print(ctx, "\n");
    } else {
        const str = arg.type.toPrintString(ctx, arg);
        rt.print(ctx, str.slice());
        rt.print(ctx, "\n");
        ctx.release(str.buf);
    }
    return rt.Error.initNull();
}

pub fn typeof(vm: *cy.VM, args: [*]const Value, _: u8) Value {
    const val = args[0];
    const typeId = val.getTypeId();
    return cy.heap.allocMetaType(vm, @intFromEnum(cy.heap.MetaTypeKind.object), typeId) catch fatal();
}

pub fn typesym(_: cy.Context, args: [*]const Value, _: u8) callconv(.C) Value {
    const val = args[0];
    switch (val.getUserTag()) {
        .float => return Value.initSymbol(@intFromEnum(Symbol.float)),
        .object => return Value.initSymbol(@intFromEnum(Symbol.object)),
        .err => return Value.initSymbol(@intFromEnum(Symbol.@"error")),
        .bool => return Value.initSymbol(@intFromEnum(Symbol.bool)),
        .map => return Value.initSymbol(@intFromEnum(Symbol.map)),
        .int => return Value.initSymbol(@intFromEnum(Symbol.int)),
        .list => return Value.initSymbol(@intFromEnum(Symbol.list)),
        .string => return Value.initSymbol(@intFromEnum(Symbol.string)),
        .array => return Value.initSymbol(@intFromEnum(Symbol.array)),
        .fiber => return Value.initSymbol(@intFromEnum(Symbol.fiber)),
        .nativeFunc,
        .closure,
        .lambda => return Value.initSymbol(@intFromEnum(Symbol.function)),
        .none => return Value.initSymbol(@intFromEnum(Symbol.none)),
        .symbol => return Value.initSymbol(@intFromEnum(Symbol.symbol)),
        .metatype => return Value.initSymbol(@intFromEnum(Symbol.metatype)),
        .pointer => return Value.initSymbol(@intFromEnum(Symbol.pointer)),
        else => fmt.panic("Unsupported {}", &.{fmt.v(val.getUserTag())}),
    }
}

fn arrayConcat(vm: *cy.VM, args: [*]const Value, _: u8) Value {
    const obj = args[0].asHeapObject();
    const slice = obj.array.getSlice();
    const rslice = args[1].asArray();
    return vm.allocArrayConcat(slice, rslice) catch fatal();
}

fn arraySlice(vm: *cy.VM, args: [*]const Value, _: u8) Value {
    const obj = args[0].asHeapObject();
    const slice = obj.array.getSlice();

    const range = args[1].asHeapObject();

    var start: i48 = undefined;
    if (!range.range.has_start) {
        start = 0;
    } else {
        start = @intCast(range.range.start);
    }
    if (start < 0) {
        return rt.prepThrowError(vm, .OutOfBounds);
    }

    var end: i48 = undefined;
    if (!range.range.has_end) {
        end = @intCast(slice.len);
    } else {
        end = @intCast(range.range.end);
    }
    if (end > slice.len) {
        return rt.prepThrowError(vm, .OutOfBounds);
    }
    if (end < start) {
        return rt.prepThrowError(vm, .OutOfBounds);
    }

    const parent = obj.array.getParent();
    vm.retainObject(parent);
    return vm.allocArraySlice(slice[@intCast(start)..@intCast(end)], parent) catch fatal();
}

fn arrayInsert(vm: *cy.VM, args: [*]const Value, _: u8) Value {
    const obj = args[0].asHeapObject();
    const slice = obj.array.getSlice();
    const idx = args[1].asInteger();
    if (idx < 0 or idx > slice.len) {
        return rt.prepThrowError(vm, .OutOfBounds);
    } 
    const insert = args[2].asArray();
    const new = vm.allocUnsetArrayObject(slice.len + insert.len) catch cy.fatal();
    const buf = new.array.getMutSlice();
    const uidx: u32 = @intCast(idx);
    std.mem.copy(u8, buf[0..uidx], slice[0..uidx]);
    std.mem.copy(u8, buf[uidx..uidx+insert.len], insert);
    std.mem.copy(u8, buf[uidx+insert.len..], slice[uidx..]);
    return Value.initNoCycPtr(new);
}

fn arrayFind(vm: *cy.VM, args: [*]const Value, _: u8) Value {
    const obj = args[0].asHeapObject();
    const slice = obj.array.getSlice();
    const needle = args[1].asArray();
    if (needle.len > 0 and needle.len <= slice.len) {
        if (needle.len == 1) {
            // One byte special case. Perform indexOfChar.
            if (cy.string.indexOfChar(slice, needle[0])) |idx| {
                return intSome(vm, @intCast(idx)) catch cy.fatal();
            }
        }
        if (cy.string.indexOf(slice, needle)) |idx| {
            return intSome(vm, @intCast(idx)) catch cy.fatal();
        }
    }
    return intNone(vm) catch cy.fatal();
}

fn arrayStartsWith(_: *cy.VM, args: [*]const Value, _: u8) Value {
    const obj = args[0].asHeapObject();
    const slice = obj.array.getSlice();
    const needle = args[1].asArray();
    return Value.initBool(std.mem.startsWith(u8, slice, needle));
}

fn arrayEndsWith(_: *cy.VM, args: [*]const Value, _: u8) Value {
    const str = args[0].asHeapObject().array.getSlice();
    const needle = args[1].asArray();
    return Value.initBool(std.mem.endsWith(u8, str, needle));
}

fn arrayDecode(vm: *cy.VM, args: [*]const Value, nargs: u8) Value {
    const encoding = Value.initSymbol(@intFromEnum(Symbol.utf8));
    return arrayDecode1(vm, &[_]Value{args[0], encoding}, nargs);
}

fn arrayDecode1(vm: *cy.VM, args: [*]const Value, _: u8) Value {
    const obj = args[0].asHeapObject();

    const encoding = bindings.getBuiltinSymbol(args[1].asSymbolId()) orelse {
        return rt.prepThrowError(vm, .InvalidArgument);
    };
    if (encoding != Symbol.utf8) {
        return rt.prepThrowError(vm, .InvalidArgument);
    }

    const parent = obj.array.getParent();
    const slice = obj.array.getSlice();
    if (cy.string.validateUtf8(slice)) |size| {
        // Since the bytes are validated, just return a slice view of the bytes.
        if (size == slice.len) {
            vm.retainObject(parent);
            return vm.allocAstringSlice(slice, parent) catch fatal();
        } else {
            vm.retainObject(parent);
            return vm.allocUstringSlice(slice, parent) catch fatal();
        }
    } else {
        return rt.prepThrowError(vm, .Unicode);
    }
}

fn arrayGetByte(_: *cy.VM, args: [*]const Value, _: u8) anyerror!Value {
    const obj = args[0].asHeapObject();
    const slice = obj.array.getSlice();
    const idx = args[1].asInteger();

    if (idx < 0 or idx >= slice.len) return error.OutOfBounds;
    return Value.initInt(@intCast(slice[@intCast(idx)]));
}

fn arrayGetInt(_: *cy.VM, args: [*]const Value, _: u8) anyerror!Value {
    const obj = args[0].asHeapObject();

    const slice = obj.array.getSlice();
    const idx = args[1].asInteger();
    const sym = try std.meta.intToEnum(Symbol, args[2].asSymbolId());
    const endian: std.builtin.Endian = switch (sym) {
        .little => .Little,
        .big => .Big,
        else => return error.InvalidArgument,
    };

    if (idx < 0 or idx + 6 > slice.len) return error.OutOfBounds;
    const uidx: usize = @intCast(idx);
    const val = std.mem.readVarInt(u48, slice[uidx..uidx+6], endian);
    return Value.initInt(@bitCast(val));
}

fn arrayGetInt32(_: *cy.VM, args: [*]const Value, _: u8) anyerror!Value {
    const obj = args[0].asHeapObject();

    const slice = obj.array.getSlice();
    const idx = args[1].asInteger();
    const sym = try std.meta.intToEnum(Symbol, args[2].asSymbolId());
    const endian: std.builtin.Endian = switch (sym) {
        .little => .Little,
        .big => .Big,
        else => return error.InvalidArgument,
    };

    if (idx < 0 or idx + 4 > slice.len) return error.OutOfBounds;
    const uidx: usize = @intCast(idx);
    const val = std.mem.readVarInt(u48, slice[uidx..uidx+4], endian);
    return Value.initInt(@intCast(val));
}

fn arrayFindAnyByte(vm: *cy.VM, args: [*]const Value, _: u8) Value {
    const obj = args[0].asHeapObject();
    const slice = obj.array.getSlice();
    const set = args[1].asArray();
    const setIsAscii = cy.string.isAstring(set);
    if (setIsAscii) {
        if (cy.string.indexOfAsciiSet(slice, set)) |idx| {
            return intSome(vm, @intCast(idx)) catch cy.fatal();
        }
    } else {
        // Slow check against every byte.
        var minIndex: u32 = cy.NullId;
        for (set) |byte| {
            if (cy.string.indexOfChar(slice, byte)) |idx| {
                if (idx < minIndex) {
                    minIndex = @intCast(idx);
                }
            }
        }
        if (minIndex != cy.NullId) {
            return intSome(vm, @intCast(minIndex)) catch cy.fatal();
        }
    }
    return intNone(vm) catch cy.fatal();
}

fn arrayFindByte(vm: *cy.VM, args: [*]const Value, _: u8) Value {
    const obj = args[0].asHeapObject();
    const slice = obj.array.getSlice();
    const byte = args[1].asInteger();

    if (cy.string.indexOfChar(slice, @intCast(byte))) |idx| {
        return intSome(vm, @intCast(idx)) catch cy.fatal();
    }
    return intNone(vm) catch cy.fatal();
}

fn arrayFmt(vm: *cy.VM, args: [*]const Value, _: u8) anyerror!Value {
    const arr = args[0].asArray();
    const kind = try std.meta.intToEnum(Symbol, args[1].asSymbolId());
    if (kind == .c) {
        var buf: std.ArrayListUnmanaged(u8) = .{};
        defer buf.deinit(vm.alloc);

        for (arr) |byte| {
            if (byte < 0 or byte > 127) {
                return error.InvalidArgument;
            }
        }
        return vm.retainOrAllocAstring(arr);
    } else {
        var base: u8 = undefined;
        var width: u8 = undefined;
        switch (kind) {
            .b => {
                base = 2;
                width = 8;
            },
            .o => {
                base = 8;
                width = 3;
            },
            .d => {
                base = 10;
                width = 3;
            },
            .x => {
                base = 16;
                width = 2;
            },
            else => return error.InvalidArgument,
        }

        var buf: std.ArrayListUnmanaged(u8) = .{};
        defer buf.deinit(vm.alloc);
        var w = buf.writer(vm.alloc);
        for (arr) |byte| {
            try std.fmt.formatInt(byte, base, .lower, .{ .width = width, .fill = '0' }, w);
        }
        return vm.retainOrAllocAstring(buf.items);
    }
}

fn arrayLen(_: *cy.VM, args: [*]const Value, _: u8) Value {
    const obj = args[0].asHeapObject();
    return Value.initInt(@intCast(obj.array.getSlice().len));
}

fn arrayTrim(vm: *cy.VM, args: [*]const Value, _: u8) anyerror!Value {
    const obj = args[0].asHeapObject();
    const slice = obj.array.getSlice();

    const trimRunes = args[2].asArray();

    var res: []const u8 = undefined;
    const mode = bindings.getBuiltinSymbol(args[1].asSymbolId()) orelse {
        return rt.prepThrowError(vm, .InvalidArgument);
    };
    switch (mode) {
        .left => res = std.mem.trimLeft(u8, slice, trimRunes),
        .right => res = std.mem.trimRight(u8, slice, trimRunes),
        .ends => res = std.mem.trim(u8, slice, trimRunes),
        else => {
            return rt.prepThrowError(vm, .InvalidArgument);
        }
    }

    return vm.allocArray(res);
}

fn arrayReplace(vm: *cy.VM, args: [*]const Value, _: u8) Value {
    const obj = args[0].asHeapObject();
    const slice = obj.array.getSlice();
    const needle = args[1].asArray();
    const replacement = args[2].asArray();

    const idxBuf = &vm.u8Buf;
    idxBuf.clearRetainingCapacity();
    defer idxBuf.ensureMaxCapOrClear(vm.alloc, 4096) catch fatal();
    const newLen = cy.string.prepReplacement(slice, needle, replacement, idxBuf.writer(vm.alloc)) catch fatal();
    const numIdxes = @divExact(idxBuf.len, 4);
    if (numIdxes > 0) {
        const new = vm.allocUnsetArrayObject(newLen) catch fatal();
        const newBuf = new.array.getMutSlice();
        const idxes = @as([*]const u32, @ptrCast(idxBuf.buf.ptr))[0..numIdxes];
        cy.string.replaceAtIdxes(newBuf, slice, @intCast(needle.len), replacement, idxes);
        return Value.initNoCycPtr(new);
    } else {
        vm.retainObject(obj);
        return Value.initNoCycPtr(obj);
    }
}

fn arrayInsertByte(vm: *cy.VM, args: [*]const Value, _: u8) Value {
    const obj = args[0].asHeapObject();
    const str = obj.array.getSlice();

    const index: i48 = args[1].asInteger();
    if (index < 0 or index > str.len) {
        return rt.prepThrowError(vm, .OutOfBounds);
    } 
    const byte: u8 = @intCast(args[2].asInteger());
    const new = vm.allocUnsetArrayObject(str.len + 1) catch cy.fatal();
    const buf = new.array.getMutSlice();
    const uidx: usize = @intCast(index);
    std.mem.copy(u8, buf[0..uidx], str[0..uidx]);
    buf[uidx] = byte;
    std.mem.copy(u8, buf[uidx+1..], str[uidx..]);
    return Value.initNoCycPtr(new);
}

fn arrayRepeat(vm: *cy.VM, args: [*]const Value, _: u8) anyerror!Value {
    const obj = args[0].asHeapObject();
    const slice = obj.array.getSlice();

    const n = args[1].asInteger();
    if (n < 0) {
        return rt.prepThrowError(vm, .InvalidArgument);
    }

    var un: u32 = @intCast(n);
    const len = un * slice.len;
    if (un > 1 and len > 0) {
        const new = try vm.allocUnsetArrayObject(len);
        const buf = new.array.getMutSlice();

        // This is already quite fast since it has good cache locality.
        // Might be faster if the front of the buffer up to a certain size was used to memcpy instead of just 1 `str`.
        var i: u32 = 0;
        var dst: u32 = 0;
        while (i < un) : (i += 1) {
            std.mem.copy(u8, buf[dst..dst + slice.len], slice);
            dst += @intCast(slice.len);
        }

        return Value.initNoCycPtr(new);
    } else {
        if (un == 0) {
            return vm.allocArray("");
        } else {
            vm.retainObject(obj);
            return Value.initNoCycPtr(obj);
        }
    }
}

fn arraySplit(vm: *cy.VM, args: [*]const Value, _: u8) anyerror!Value {
    const obj = args[0].asHeapObject();
    const slice = obj.array.getSlice();
    const delim = args[1].asArray();

    const res = try vm.allocEmptyList();
    if (delim.len == 0) {
        return res;
    }
    const list = res.asHeapObject();

    const parent = obj.array.getParent();
    var iter = std.mem.split(u8, slice, delim);
    while (iter.next()) |part| {
        vm.retainObject(parent);
        const new = try vm.allocArraySlice(part, parent);
        try list.list.append(vm.alloc, new);
    }
    return res;
}

fn arrayCall(vm: *cy.VM, args: [*]const Value, _: u8) anyerror!Value {
    const str = try vm.getOrBufPrintValueRawStr(&cy.tempBuf, args[0]);
    return vm.allocArray(str);
}

fn fiberStatus(vm: *cy.VM, args: [*]const Value, _: u8) Value {
    const fiber = args[0].castHeapObject(*vmc.Fiber);

    if (vm.curFiber == fiber) {
        return Value.initSymbol(@intFromEnum(Symbol.running));
    } else {
        // Check if done.
        if (fiber.pcOffset == cy.NullId) {
            return Value.initSymbol(@intFromEnum(Symbol.done));
        } else {
            return Value.initSymbol(@intFromEnum(Symbol.paused));
        }
    }
}

fn metatypeId(_: *cy.VM, args: [*]const Value, _: u8) Value {
    const obj = args[0].asHeapObject();
    return Value.initInt(obj.metatype.type);
}

fn pointerAsObject(vm: *cy.VM, args: [*]const Value, _: u8) Value {
    const ptr = args[0].asHeapObject().pointer.ptr;
    vm.retainObject(@ptrCast(@alignCast(ptr)));
    return Value.initPtr(ptr);
}

fn pointerAddr(_: *cy.VM, args: [*]const Value, _: u8) Value {
    const obj = args[0].asHeapObject();
    return Value.initInt(@bitCast(@as(u48, (@intCast(@intFromPtr(obj.pointer.ptr))))));
}

fn pointerFromCstr(vm: *cy.VM, args: [*]const Value, _: u8) anyerror!Value {
    if (cy.isWasm) return vm.prepPanic("Unsupported.");
    const obj = args[0].asHeapObject();
    const raw: [*]const u8 = @ptrCast(obj.pointer.ptr);
    const off: u48 = @bitCast(args[1].asInteger());
    const bytes = std.mem.span(@as([*:0]const u8, @ptrCast(raw + off)));
    return vm.allocArray(bytes);
}

fn pointerGet(vm: *cy.VM, args: [*]const Value, _: u8) anyerror!Value {
    const obj = args[0].asHeapObject();
    const off = args[1].asInteger();
    const ctype = try std.meta.intToEnum(Symbol, args[2].asSymbolId());

    const raw = obj.pointer.ptr;
    const uoff: u48 = @bitCast(off);
    switch (ctype) {
        .voidPtr => {
            const addr: usize = @intFromPtr(raw) + @as(usize, @intCast(uoff));
            const val = @as(*?*anyopaque, @ptrFromInt(addr)).*;
            return vm.allocPointer(val);
        },
        else => {
            return error.InvalidArgument;
        }
    }
}

fn pointerSet(_: *cy.VM, args: [*]const Value, _: u8) anyerror!Value {
    const obj = args[0].asHeapObject();
    const idx = args[1].asInteger();
    const ctype = try std.meta.intToEnum(Symbol, args[2].asSymbolId());
    const val = args[3];
    const rawPtr = obj.pointer.ptr;
    const valT = val.getTypeId();
    const uidx: u48 = @bitCast(idx);
    switch (ctype) {
        .int => {
            switch (valT) {
                bt.Integer => {
                    const addr: usize = @intFromPtr(rawPtr) + @as(usize, @intCast(uidx));
                    @as(*i32, @ptrFromInt(addr)).* = @intCast(val.asInteger());
                    return Value.Void;
                },
                else => {
                    return error.InvalidArgument;
                }
            }
        },
        .voidPtr => {
            switch (valT) {
                bt.Pointer => {
                    const addr: usize = @intFromPtr(rawPtr) + @as(usize, @intCast(uidx));
                    @as(*?*anyopaque, @ptrFromInt(addr)).* = val.asHeapObject().pointer.ptr;
                    return Value.Void;
                },
                bt.ExternFunc => {
                    const addr: usize = @intFromPtr(rawPtr) + @as(usize, @intCast(uidx));
                    @as(*?*anyopaque, @ptrFromInt(addr)).* = val.asHeapObject().externFunc.ptr;
                    return Value.Void;
                },
                else => {
                    return error.InvalidArgument;
                }
            }
        },
        else => {
            return error.InvalidArgument;
        }
    }
}

fn pointerToArray(vm: *cy.VM, args: [*]const Value, _: u8) anyerror!Value {
    const obj = args[0].asHeapObject();
    const off: u48 = @bitCast(args[1].asInteger());
    const len: u48 = @bitCast(args[2].asInteger());
    const raw: [*]const u8 = @ptrCast(obj.pointer.ptr);
    const uoff: usize = @intCast(off);
    return vm.allocArray(raw[uoff..@intCast(uoff+len)]);
}

fn pointerCall(vm: *cy.VM, args: [*]const Value, _: u8) Value {
    const val = args[0];
    if (val.isPointerT()) {
        vm.retain(val);
        return val;
    } else if (val.isInteger()) {
        const i: usize = @intCast(val.asInteger());
        return cy.heap.allocPointer(vm, @ptrFromInt(i)) catch fatal();
    } else {
        return vm.prepPanic("Not a `pointer`.");
    }
}

fn externFuncAddr(_: *cy.VM, args: [*]const Value, _: u8) Value {
    const obj = args[0].asHeapObject();
    return Value.initInt(@bitCast(@as(u48, (@intCast(@intFromPtr(obj.externFunc.ptr))))));
}

fn errorSym(_: *cy.VM, args: [*]const Value, _: u8) Value {
    const recv = args[0];
    return Value.initSymbol(recv.asErrorSymbol());
}

fn errorCall(vm: *cy.VM, args: [*]const Value, _: u8) Value {
    const val = args[0];
    if (val.isPointer()) {
        return rt.prepThrowError(vm, .InvalidArgument);
    } else {
        if (val.isSymbol()) {
            return Value.initErrorSymbol(@intCast(val.asSymbolId()));
        } else if (val.isEnum()) {
            const enumT = val.getEnumType();
            const enumv = val.getEnumValue();
            const name = vm.types[enumT].sym.cast(.enum_t).getValueSym(enumv).name();
            const symId = vm.ensureSymbol(name) catch cy.unexpected();
            return Value.initErrorSymbol(symId);
        } else {
            return rt.prepThrowError(vm, .InvalidArgument);
        }
    }
}

fn intFmt(vm: *cy.VM, args: [*]const Value, _: u8) anyerror!Value {
    const val = args[0].asInteger();
    const kind = try std.meta.intToEnum(Symbol, args[1].asSymbolId());
    return intFmtExt(vm, val, kind, .{});
}

fn intFmt2(vm: *cy.VM, args: [*]const Value, _: u8) anyerror!Value {
    const val = args[0].asInteger();
    const kind = try std.meta.intToEnum(Symbol, args[1].asSymbolId());
    const optsv = args[2].castHeapObject(*cy.heap.Map);
    var opts: IntFmtOptions = .{};
    if (optsv.map().getByString("pad")) |pad| {
        if (!pad.isInteger()) return error.InvalidArgument;
        const padv = pad.asInteger();
        if (padv < 0 or padv > 127) return error.InvalidArgument;
        opts.pad = @intCast(padv);
    }
    if (optsv.map().getByString("width")) |width| {
        if (!width.isInteger()) return error.InvalidArgument;
        const widthv = width.asInteger();
        if (widthv < 0) return error.InvalidArgument;
        opts.width = @intCast(widthv);
    }
    return intFmtExt(vm, val, kind, opts);
}

const IntFmtOptions = struct {
    pad: ?u8 = null,
    width: ?usize = null,
};

fn intFmtExt(vm: *cy.VM, val: i48, kind: Symbol, opts: IntFmtOptions) !Value {
    if (kind == .c) {
        if (val < 0 or val > 127) {
            return error.InvalidArgument;
        }
        const uchar: u8 = @intCast(val);
        return vm.retainOrAllocAstring(&.{uchar});
    } else {
        const base: u8 = switch (kind) {
            .b => 2,
            .o => 8,
            .d => 10,
            .x => 16,
            else => return error.InvalidArgument,
        };
        var buf: [48]u8 = undefined;
        var fb = std.io.fixedBufferStream(&buf);
        if (val < 0) {
            try std.fmt.formatInt(val, base, .lower, .{ .fill = opts.pad orelse ' ', .width = opts.width }, fb.writer());
        } else {
            try std.fmt.formatInt(@as(u48, @bitCast(val)), base, .lower, .{ .fill = opts.pad orelse ' ', .width = opts.width }, fb.writer());
        }
        return vm.retainOrAllocAstring(fb.getWritten());
    }
}

fn intCall(_: *cy.VM, args: [*]const Value, _: u8) Value {
    const val = args[0];
    switch (val.getUserTag()) {
        .float => {
            return Value.initInt(@intFromFloat(@trunc(val.asF64())));
        },
        .string => {
            var str = val.asString();
            if (std.mem.indexOfScalar(u8, str, '.')) |idx| {
                str = str[0..idx];
            }
            const res = std.fmt.parseInt(i32, str, 10) catch {
                return Value.initInt(0);
            };
            return Value.initInt(res);
        },
        .enumT => return Value.initInt(val.getEnumValue()),
        .symbol => return Value.initInt(@intCast(val.val & @as(u64, 0xFF))),
        .int => {
            return val;
        },
        else => {
            return Value.initInt(0);
        }
    }
}

fn boolCall(_: *cy.VM, args: [*]const Value, _: u8) Value {
    return Value.initBool(args[0].toBool());
}

fn floatCall(vm: *cy.VM, args: [*]const Value, _: u8) Value {
    const val = args[0];
    switch (val.getUserTag()) {
        .float => return val,
        .string => {
            const res = std.fmt.parseFloat(f64, val.asString()) catch {
                return Value.initF64(0);
            };
            return Value.initF64(res);
        },
        .enumT => return Value.initF64(@floatFromInt(val.getEnumValue())),
        .symbol => return Value.initF64(@floatFromInt(val.val & @as(u64, 0xFF))),
        .int => return Value.initF64(@floatFromInt(val.asInteger())),
        .none => return Value.initF64(0),
        .bool => return Value.initF64(if (val.asBool()) 1 else 0),
        else => {
            vm.release(val);
            return vm.prepPanic("Not a type that can be converted to `float`.");
        }
    }
}

pub fn intNone(vm: *cy.VM) !Value {
    return vm.allocObjectSmall(OptionInt, &.{ Value.initInt(0), Value.initInt(0) });
}

pub fn intSome(vm: *cy.VM, v: i48) !Value {
    return vm.allocObjectSmall(OptionInt, &.{ Value.initInt(1), Value.initInt(v) });
}

pub fn anyNone(vm: *cy.VM) !Value {
    return vm.allocObjectSmall(OptionAny, &.{ Value.initInt(0), Value.initInt(0) });
}

pub fn anySome(vm: *cy.VM, v: Value) !Value {
    return vm.allocObjectSmall(OptionAny, &.{ Value.initInt(1), v });
}

pub fn TupleNone(vm: *cy.VM) !Value {
    return vm.allocObjectSmall(OptionTuple, &.{ Value.initInt(0), Value.initInt(0) });
}

pub fn TupleSome(vm: *cy.VM, v: Value) !Value {
    return vm.allocObjectSmall(OptionTuple, &.{ Value.initInt(1), v });
}

pub fn MapNone(vm: *cy.VM) !Value {
    return vm.allocObjectSmall(OptionMap, &.{ Value.initInt(0), Value.initInt(0) });
}

pub fn MapSome(vm: *cy.VM, v: Value) !Value {
    return vm.allocObjectSmall(OptionMap, &.{ Value.initInt(1), v });
}

pub fn ArrayNone(vm: *cy.VM) !Value {
    return vm.allocObjectSmall(OptionArray, &.{ Value.initInt(0), Value.initInt(0) });
}

pub fn ArraySome(vm: *cy.VM, v: Value) !Value {
    return vm.allocObjectSmall(OptionArray, &.{ Value.initInt(1), v });
}

pub fn StringNone(vm: *cy.VM) !Value {
    return vm.allocObjectSmall(OptionString, &.{ Value.initInt(0), Value.initInt(0) });
}

pub fn StringSome(vm: *cy.VM, v: Value) !Value {
    return vm.allocObjectSmall(OptionString, &.{ Value.initInt(1), v });
}