const std = @import("std");
const stdx = @import("stdx");
const t = stdx.testing;

const cy = @import("cyber.zig");
const NodeId = cy.NodeId;
const Parser = cy.Parser;
const log = cy.log.scoped(.cdata);

pub const EncodeListContext = struct {
    writer: std.ArrayListUnmanaged(u8).Writer,
    tmp_buf: *std.ArrayList(u8),
    cur_indent: u32,
    user_ctx: ?*anyopaque,

    pub fn indent(self: *EncodeListContext) !void {
        try self.writer.writeByteNTimes(' ', self.cur_indent * 4);
    }

    pub fn encodeList(self: *EncodeListContext, val: anytype, cb: fn (*EncodeListContext, @TypeOf(val)) anyerror!void) !void {
        _ = try self.writer.write("[\n");

        var list_ctx = EncodeListContext{
            .writer = self.writer,
            .tmp_buf = self.tmp_buf,
            .cur_indent = self.cur_indent + 1,
            .user_ctx = self.user_ctx,
        };
        try cb(&list_ctx, val);

        try self.indent();
        _ = try self.writer.write("]");
    }
    
    pub fn encodeMap(self: *EncodeListContext, val: anytype, encode_map: fn (*EncodeMapContext, @TypeOf(val)) anyerror!void) !void {
        _ = try self.writer.write("{\n");

        var map_ctx = EncodeMapContext{
            .writer = self.writer,
            .tmp_buf = self.tmp_buf,
            .cur_indent = self.cur_indent + 1,
            .user_ctx = self.user_ctx,
        };
        try encode_map(&map_ctx, val);

        try self.indent();
        _ = try self.writer.write("}");
    }

    pub fn encodeBool(self: *EncodeListContext, b: bool) !void {
        try Common.encodeBool(self.writer, b);
    }

    pub fn encodeFloat(self: *EncodeListContext, f: f64) !void {
        try Common.encodeFloat(self.writer, f);
    }

    pub fn encodeInt(self: *EncodeListContext, i: i48) !void {
        try Common.encodeInt(self.writer, i);
    }

    pub fn encodeString(self: *EncodeListContext, str: []const u8) !void {
        try Common.encodeString(self.tmp_buf, self.writer, str);
    }
};

/// TODO: Rename to EncodeRootContext
pub const EncodeValueContext = struct {
    writer: std.ArrayListUnmanaged(u8).Writer,
    tmp_buf: *std.ArrayList(u8),
    cur_indent: u32,
    user_ctx: ?*anyopaque,

    fn indent(self: *EncodeValueContext) !void {
        try self.writer.writeByteNTimes(' ', self.cur_indent * 4);
    }

    pub fn encodeList(self: *EncodeValueContext, val: anytype, encode_list: fn (*EncodeListContext, @TypeOf(val)) anyerror!void) !void {
        _ = try self.writer.print("[\n", .{});

        var list_ctx = EncodeListContext{
            .writer = self.writer,
            .tmp_buf = self.tmp_buf,
            .cur_indent = self.cur_indent + 1,
            .user_ctx = self.user_ctx,
        };
        try encode_list(&list_ctx, val);

        try self.indent();
        _ = try self.writer.write("]");
    }

    pub fn encodeMap(self: *EncodeValueContext, val: anytype, encode_map: fn (*EncodeMapContext, @TypeOf(val)) anyerror!void) !void {
        _ = try self.writer.write("{\n");

        var map_ctx = EncodeMapContext{
            .writer = self.writer,
            .tmp_buf = self.tmp_buf,
            .cur_indent = self.cur_indent + 1,
            .user_ctx = self.user_ctx,
        };
        try encode_map(&map_ctx, val);

        try self.indent();
        _ = try self.writer.write("}");
    }

    pub fn encodeBool(self: *EncodeValueContext, b: bool) !void {
        try Common.encodeBool(self.writer, b);
    }

    pub fn encodeFloat(self: *EncodeValueContext, f: f64) !void {
        try Common.encodeFloat(self.writer, f);
    }

    pub fn encodeInt(self: *EncodeValueContext, i: i48) !void {
        try Common.encodeInt(self.writer, i);
    }

    pub fn encodeString(self: *EncodeValueContext, str: []const u8) !void {
        try Common.encodeString(self.tmp_buf, self.writer, str);
    }
};

pub const EncodeMapContext = struct {
    writer: std.ArrayListUnmanaged(u8).Writer,
    tmp_buf: *std.ArrayList(u8),
    cur_indent: u32,
    user_ctx: ?*anyopaque,

    fn indent(self: *EncodeMapContext) !void {
        try self.writer.writeByteNTimes(' ', self.cur_indent * 4);
    }

    pub fn encodeSlice(self: *EncodeMapContext, key: []const u8, slice: anytype, encode_value: fn (*EncodeValueContext, anytype) anyerror!void) !void {
        try self.indent();
        _ = try self.writer.print("{s}: [\n", .{key});

        var val_ctx = EncodeValueContext{
            .writer = self.writer,
            .tmp_buf = self.tmp_buf,
            .cur_indent = self.cur_indent + 1,
            .user_ctx = self.user_ctx,
        };
        self.cur_indent += 1;
        for (slice) |it| {
            try self.indent();
            try encode_value(&val_ctx, it);
            _ = try self.writer.write(",\n");
        }
        self.cur_indent -= 1;

        try self.indent();
        _ = try self.writer.write("],\n");
    }

    pub fn encodeList(self: *EncodeMapContext, key: []const u8, val: anytype, encode_list: fn (*EncodeListContext, @TypeOf(val)) anyerror!void) !void {
        try self.indent();
        _ = try self.writer.print("{s}: [\n", .{key});

        var list_ctx = EncodeListContext{
            .writer = self.writer,
            .tmp_buf = self.tmp_buf,
            .cur_indent = self.cur_indent + 1,
            .user_ctx = self.user_ctx,
        };
        try encode_list(&list_ctx, val);

        try self.indent();
        _ = try self.writer.write("]\n");
    }

    pub fn encodeMap(self: *EncodeMapContext, key: []const u8, val: anytype, encode_map: fn (*EncodeMapContext, @TypeOf(val)) anyerror!void) !void {
        try self.indent();
        _ = try self.writer.print("{s}: {{\n", .{key});

        var map_ctx = EncodeMapContext{
            .writer = self.writer,
            .tmp_buf = self.tmp_buf,
            .cur_indent = self.cur_indent + 1,
            .user_ctx = self.user_ctx,
        };
        try encode_map(&map_ctx, val);

        try self.indent();
        _ = try self.writer.write("},\n");
    }

    pub fn encodeMap2(self: *EncodeMapContext, key: []const u8, val: anytype, encode_map: fn (*EncodeMapContext, anytype) anyerror!void) !void {
        try self.indent();
        _ = try self.writer.print("{s}: ", .{ key });

        _ = try self.writer.write("{\n");

        var map_ctx = EncodeMapContext{
            .writer = self.writer,
            .tmp_buf = self.tmp_buf,
            .cur_indent = self.cur_indent + 1,
            .user_ctx = self.user_ctx,
        };
        try encode_map(&map_ctx, val);

        try self.indent();
        _ = try self.writer.write("}\n");
    }

    pub fn encode(self: *EncodeMapContext, key: []const u8, val: anytype) !void {
        try self.indent();
        _ = try self.writer.print("{s}: ", .{key});
        try self.encodeValue(val);
        _ = try self.writer.write(",\n");
    }

    pub fn encodeString(self: *EncodeMapContext, key: []const u8, val: []const u8) !void {
        try self.indent();
        _ = try self.writer.print("{s}: ", .{key});
        try Common.encodeString(self.tmp_buf, self.writer, val);
        _ = try self.writer.write(",\n");
    }

    pub fn encodeInt(self: *EncodeMapContext, key: []const u8, i: i48) !void {
        try self.indent();
        _ = try self.writer.print("{s}: ", .{key});
        try Common.encodeInt(self.writer, i);
        _ = try self.writer.write(",\n");
    }

    pub fn encodeFloat(self: *EncodeMapContext, key: []const u8, f: f64) !void {
        try self.indent();
        _ = try self.writer.print("{s}: ", .{key});
        try Common.encodeFloat(self.writer, f);
        _ = try self.writer.write(",\n");
    }

    pub fn encodeBool(self: *EncodeMapContext, key: []const u8, b: bool) !void {
        try self.indent();
        _ = try self.writer.print("{s}: ", .{key});
        try Common.encodeBool(self.writer, b);
        _ = try self.writer.write(",\n");
    }

    pub fn encodeAnyToMap(self: *EncodeMapContext, key: anytype, val: anytype, encode_map: fn (*EncodeMapContext, @TypeOf(val)) anyerror!void) !void {
        try self.encodeAnyKey_(key);
        _ = try self.writer.write("{\n");

        var map_ctx = EncodeMapContext{
            .writer = self.writer,
            .tmp_buf = self.tmp_buf,
            .cur_indent = self.cur_indent + 1,
            .user_ctx = self.user_ctx,
        };
        try encode_map(&map_ctx, val);

        try self.indent();
        _ = try self.writer.write("}\n");
    }

    fn encodeAnyKey_(self: *EncodeMapContext, key: anytype) !void {
        try self.indent();
        const T = @TypeOf(key);
        switch (T) {
            // Don't support string types since there can be many variations. Use `encode` instead.
            u32 => {
                _ = try self.writer.print("{}: ", .{key});
            },
            else => {
                log.tracev("unsupported: {s}", .{@typeName(T)});
                return error.Unsupported;
            },
        }
    }

    pub fn encodeAnyToString(self: *EncodeMapContext, key: anytype, val: []const u8) !void {
        try self.encodeAnyKey_(key);
        try Common.encodeString(self.tmp_buf, self.writer, val);
        _ = try self.writer.write(",\n");
    }

    pub fn encodeAnyToValue(self: *EncodeMapContext, key: anytype, val: anytype) !void {
        try self.encodeAnyKey_(key);
        try self.encodeValue(val);
        _ = try self.writer.write(",\n");
    }

    fn encodeValue(self: *EncodeMapContext, val: anytype) !void {
        const T = @TypeOf(val);
        switch (T) {
            bool,
            u32 => {
                _ = try self.writer.print("{}", .{val});
            },
            else => {
                @compileError("unsupported: " ++ @typeName(T));
            },
        }
    }
};

const Common = struct {
    fn encodeString(tmpBuf: *std.ArrayList(u8), writer: anytype, str: []const u8) !void {
        tmpBuf.clearRetainingCapacity();
        if (std.mem.indexOfScalar(u8, str, '\n') == null) {
            _ = replaceIntoList(u8, str, "'", "\\'", tmpBuf);
            _ = try writer.print("'{s}'", .{tmpBuf.items});
        } else {
            _ = replaceIntoList(u8, str, "`", "\\`", tmpBuf);
            _ = try writer.print("`{s}`", .{tmpBuf.items});
        }
    }

    fn encodeBool(writer: anytype, b: bool) !void {
        _ = try writer.print("{}", .{b});
    }

    fn encodeInt(writer: anytype, i: i48) !void {
        try writer.print("{}", .{i});
    }

    fn encodeFloat(writer: anytype, f: f64) !void {
        if (cy.Value.floatCanBeInteger(f)) {
            try writer.print("{d:.0}.0", .{f});
        } else {
            try writer.print("{d}", .{f});
        }
    }
};

pub fn encode(alloc: std.mem.Allocator, user_ctx: ?*anyopaque, val: anytype, encode_value: fn (*EncodeValueContext, anytype) anyerror!void) ![]const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    var tmp_buf = std.ArrayList(u8).init(alloc);
    defer tmp_buf.deinit();
    var val_ctx = EncodeValueContext{
        .writer = buf.writer(alloc),
        .cur_indent = 0,
        .user_ctx = user_ctx,
        .tmp_buf = &tmp_buf,
    };
    try encode_value(&val_ctx, val);
    return buf.toOwnedSlice(alloc);
}

pub const DecodeListIR = struct {
    alloc: std.mem.Allocator,
    ast: cy.ast.AstView,
    arr: []const NodeId,

    fn init(alloc: std.mem.Allocator, ast: cy.ast.AstView, list_id: NodeId) !DecodeListIR {
        const list = ast.node(list_id);
        if (list.type() != .arrayLit) {
            return error.NotAList;
        }

        var new = DecodeListIR{
            .alloc = alloc,
            .ast = ast,
            .arr = &.{},
        };

        // Construct list.
        var buf: std.ArrayListUnmanaged(NodeId) = .{};
        if (list.data.arrayLit.numArgs > 0) {
            var item_id = list.data.arrayLit.argHead;
            while (item_id != cy.NullNode) {
                const item = ast.node(item_id);
                try buf.append(alloc, item_id);
                item_id = item.next();
            }
        }
        new.arr = try buf.toOwnedSlice(alloc);
        return new;
    }

    pub fn deinit(self: *DecodeListIR) void {
        self.alloc.free(self.arr);
    }

    pub fn getIndex(self: DecodeListIR, idx: usize) DecodeValueIR {
        return DecodeValueIR{
            .alloc = self.alloc,
            .ast = self.ast,
            .exprId = self.arr[idx],
        };
    }

    pub fn decodeMap(self: DecodeListIR, idx: u32) !DecodeMapIR {
        if (idx < self.arr.len) {
            return try DecodeMapIR.init(self.alloc, self.ast, self.arr[idx]);
        } else return error.NoSuchEntry;
    }
};

pub const DecodeMapIR = struct {
    alloc: std.mem.Allocator,
    ast: cy.ast.AstView,

    /// Preserve order of entries.
    map: std.StringArrayHashMapUnmanaged(NodeId),

    fn init(alloc: std.mem.Allocator, ast: cy.ast.AstView, map_id: NodeId) !DecodeMapIR {
        const map = ast.node(map_id);
        if (map.type() != .recordLit) {
            return error.NotAMap;
        }

        var new = DecodeMapIR{
            .alloc = alloc,
            .ast = ast,
            .map = .{},
        };

        // Parse literal into map.
        var entry_id = map.recordLit_argHead();
        while (entry_id != cy.NullNode) {
            const entry = ast.node(entry_id);
            const key = ast.node(entry.keyValue_key());
            switch (key.type()) {
                .binLit,
                .octLit,
                .hexLit,
                .decLit,
                .floatLit,
                .ident => {
                    const str = ast.nodeString(key);
                    try new.map.put(alloc, str, entry.keyValue_value());
                },
                else => return error.Unsupported,
            }
            entry_id = entry.next();
        }
        return new;
    }

    pub fn deinit(self: *DecodeMapIR) void {
        self.map.deinit(self.alloc);
    }

    pub fn iterator(self: DecodeMapIR) std.StringArrayHashMapUnmanaged(NodeId).Iterator {
        return self.map.iterator();
    }

    pub fn getValue(self: DecodeMapIR, key: []const u8) DecodeValueIR {
        return DecodeValueIR{
            .alloc = self.alloc,
            .ast = self.ast,
            .exprId = self.map.get(key).?,
        };
    }
    
    pub fn allocString(self: DecodeMapIR, key: []const u8) ![]const u8 {
        if (self.map.get(key)) |val_id| {
            const val_n = self.ast.node(val_id);
            if (val_n.type() == .raw_string_lit) {
                const token_s = self.ast.nodeString(val_n);
                return try self.alloc.dupe(u8, token_s);
            } else if (val_n.type() == .stringLit) {
                const token_s = self.ast.nodeString(val_n);
                var buf = std.ArrayList(u8).init(self.alloc);
                defer buf.deinit();

                try buf.resize(token_s.len);
                const str = try cy.unescapeString(buf.items, token_s, true);
                buf.items.len = str.len;
                return buf.toOwnedSlice();
            } else if (val_n.type() == .stringTemplate) {
                const str = self.ast.node(val_n.data.stringTemplate.strHead);
                if (str.next() == cy.NullNode) {
                    const token_s = self.ast.nodeString(str);
                    var buf = std.ArrayList(u8).init(self.alloc);
                    defer buf.deinit();
                    _ = replaceIntoList(u8, token_s, "\\`", "`", &buf);
                    return buf.toOwnedSlice();
                }
            }
            return error.NotAString;
        } else return error.NoSuchEntry;
    }

    pub fn getU32(self: DecodeMapIR, key: []const u8) !u32 {
        if (self.map.get(key)) |val_id| {
            const val_n = self.ast.node(val_id);
            switch (val_n.type()) {
                .binLit => {
                    const str = self.ast.nodeString(val_n)[2..];
                    return try std.fmt.parseInt(u32, str, 2);
                },
                .octLit => {
                    const str = self.ast.nodeString(val_n)[2..];
                    return try std.fmt.parseInt(u32, str, 8);
                },
                .hexLit => {
                    const str = self.ast.nodeString(val_n)[2..];
                    return try std.fmt.parseInt(u32, str, 16);
                },
                .decLit => {
                    const str = self.ast.nodeString(val_n);
                    return try std.fmt.parseInt(u32, str, 10);
                },
                else => return error.NotANumber,
            }
        } else return error.NoSuchEntry;
    }

    pub fn getBool(self: DecodeMapIR, key: []const u8) !bool {
        return self.getBoolOpt(key) orelse return error.NoSuchEntry;
    }

    pub fn getBoolOpt(self: DecodeMapIR, key: []const u8) !?bool {
        if (self.map.get(key)) |val_id| {
            const val_n = self.ast.node(val_id);
            if (val_n.type() == .trueLit) {
                return true;
            } else if (val_n.type() == .falseLit) {
                return false;
            } else return error.NotABool;
        } else return null;
    }

    pub fn decodeList(self: DecodeMapIR, key: []const u8) !DecodeListIR {
        if (self.map.get(key)) |val_id| {
            return DecodeListIR.init(self.alloc, self.ast, val_id);
        } else return error.NoSuchEntry;
    }

    pub fn decodeMap(self: DecodeMapIR, key: []const u8) !DecodeMapIR {
        if (self.map.get(key)) |val_id| {
            return try DecodeMapIR.init(self.alloc, self.ast, val_id);
        } else return error.NoSuchEntry;
    }
};

// Currently uses Cyber parser.
pub fn decodeMap(alloc: std.mem.Allocator, parser: *Parser, ctx: anytype, out: anytype, decode_map: fn (DecodeMapIR, @TypeOf(ctx), @TypeOf(out)) anyerror!void, cdata: []const u8) !void {
    const res = try parser.parse(cdata, .{});
    if (res.has_error) {
        return error.ParseError;
    }

    const root = res.ast.node(res.root_id);
    if (root.data.root.bodyHead == cy.NullNode) {
        return error.NotAMap;
    }
    const first_stmt = res.ast.node(root.root_bodyHead());
    if (first_stmt.type() != .exprStmt) {
        return error.NotAMap;
    }

    var map = try DecodeMapIR.init(alloc, res.ast, first_stmt.exprStmt_child());
    defer map.deinit();
    try decode_map(map, ctx, out);
}

pub fn decode(alloc: std.mem.Allocator, parser: *Parser, cyon: []const u8) !DecodeValueIR {
    const res = try parser.parse(cyon, .{});
    if (res.has_error) {
        return error.ParseError;
    }

    const root = res.ast.node(res.root_id);
    if (root.data.root.bodyHead == cy.NullNode) {
        return error.NotAValue;
    }
    const first_stmt = res.ast.node(root.data.root.bodyHead);
    if (first_stmt.type() != .exprStmt) {
        return error.NotAValue;
    }

    return DecodeValueIR{
        .alloc = alloc, 
        .ast = res.ast,
        .exprId = first_stmt.data.exprStmt.child,
    };
}

const ValueType = enum {
    list,
    map,
    string,
    integer,
    float,
    bool,
};

pub const DecodeValueIR = struct {
    alloc: std.mem.Allocator,
    ast: cy.ast.AstView,
    exprId: NodeId,

    pub fn getValueType(self: DecodeValueIR) ValueType {
        const node = self.ast.node(self.exprId);
        switch (node.type()) {
            .arrayLit => return .list,
            .recordLit => return .map,
            .raw_string_lit,
            .stringLit => return .string,
            .hexLit,
            .binLit,
            .octLit,
            .decLit => return .integer,
            .floatLit => return .float,
            .trueLit => return .bool,
            .falseLit => return .bool,
            else => cy.panicFmt("unsupported {}", .{node.type()}),
        }
    }

    pub fn getList(self: DecodeValueIR) !DecodeListIR {
        return DecodeListIR.init(self.alloc, self.ast, self.exprId);
    }

    pub fn getMap(self: DecodeValueIR) !DecodeMapIR {
        return DecodeMapIR.init(self.alloc, self.ast, self.exprId);
    }

    pub fn allocString(self: DecodeValueIR) ![]u8 {
        const node = self.ast.node(self.exprId);
        const token_s = self.ast.nodeString(node);
        var buf = std.ArrayList(u8).init(self.alloc);
        defer buf.deinit();
        try buf.resize(token_s.len);
        const str = try cy.unescapeString(buf.items, token_s, true);
        buf.items.len = str.len;
        return try buf.toOwnedSlice();
    }

    pub fn getF64(self: DecodeValueIR) !f64 {
        const node = self.ast.node(self.exprId);
        const token_s = self.ast.nodeString(node);
        return try std.fmt.parseFloat(f64, token_s);
    }

    pub fn getInt(self: DecodeValueIR) !i48 {
        const node = self.ast.node(self.exprId);
        const token_s = self.ast.nodeString(node);
        return try std.fmt.parseInt(i48, token_s, 10);
    }

    pub fn getBool(self: DecodeValueIR) bool {
        const node = self.ast.node(self.exprId);
        if (node.type() == .trueLit) {
            return true;
        } else if (node.type() == .falseLit) {
            return false;
        } else {
            cy.panicFmt("Unsupported type: {}", .{node.type()});
        }
    }
};

const TestRoot = struct {
    name: []const u8,
    list: []const TestListItem,
    map: []const TestMapItem,
};

const TestListItem = struct {
    field: u32,
};

const TestMapItem = struct {
    id: u32,
    val: []const u8,
};

test "encode" {
    var root = TestRoot{
        .name = "project",
        .list = &.{
            .{ .field = 1 },
            .{ .field = 2 },
        },
        .map = &.{
            .{ .id = 1, .val = "foo" },
            .{ .id = 2, .val = "bar" },
            .{ .id = 3, .val = "ba'r" },
            .{ .id = 4, .val = "bar\nbar" },
            .{ .id = 5, .val = "bar `bar`\nbar" },
        },
    };

    const S = struct {
        fn encodeRoot(ctx: *EncodeMapContext, val: TestRoot) anyerror!void {
            try ctx.encodeString("name", val.name);
            try ctx.encodeSlice("list", val.list, encodeValue);
            try ctx.encodeMap("map", val.map, encodeMap);
        }
        fn encodeMap(ctx: *EncodeMapContext, val: []const TestMapItem) anyerror!void {
            for (val) |it| {
                try ctx.encodeAnyToString(it.id, it.val);
            }
        }
        fn encodeItem(ctx: *EncodeMapContext, val: TestListItem) anyerror!void {
            try ctx.encode("field", val.field);
        }
        fn encodeValue(ctx: *EncodeValueContext, val: anytype) !void {
            const T = @TypeOf(val);
            if (T == TestRoot) {
                try ctx.encodeMap(val, encodeRoot);
            } else if (T == TestListItem) {
                try ctx.encodeMap(val, encodeItem);
            } else {
                cy.panicFmt("unsupported: {s}", .{@typeName(T)});
            }
        }
    };

    const res = try encode(t.alloc, null, root, S.encodeValue);
    defer t.alloc.free(res);
    try t.eqStr(res,
        \\{
        \\    name: 'project',
        \\    list: [
        \\        {
        \\            field: 1,
        \\        },
        \\        {
        \\            field: 2,
        \\        },
        \\    ],
        \\    map: {
        \\        1: 'foo',
        \\        2: 'bar',
        \\        3: 'ba\'r',
        \\        4: `bar
        \\bar`,
        \\        5: `bar \`bar\`
        \\bar`,
        \\    },
        \\}
    );
}

test "decodeMap" {
    const S = struct {
        fn decodeRoot(map: DecodeMapIR, _: void, root: *TestRoot) anyerror!void {
            root.name = try map.allocString("name");

            var list: std.ArrayListUnmanaged(TestListItem) = .{};
            var list_ir = try map.decodeList("list");
            defer list_ir.deinit();
            var i: u32 = 0;
            while (i < list_ir.arr.len) : (i += 1) {
                var item: TestListItem = undefined;
                var item_map = try list_ir.decodeMap(i);
                defer item_map.deinit();
                item.field = try item_map.getU32("field");
                try list.append(t.alloc, item);
            }
            root.list = try list.toOwnedSlice(t.alloc);

            var map_items: std.ArrayListUnmanaged(TestMapItem) = .{};
            var map_ = try map.decodeMap("map");
            defer map_.deinit();
            var iter = map_.iterator();
            while (iter.next()) |entry| {
                const key = try std.fmt.parseInt(u32, entry.key_ptr.*, 10);
                const value = try map_.allocString(entry.key_ptr.*);
                try map_items.append(t.alloc, .{ .id = key, .val = value });
            }
            root.map = try map_items.toOwnedSlice(t.alloc);
        }
    };

    var parser = try Parser.init(t.alloc);
    defer parser.deinit();

    var root: TestRoot = undefined;
    try decodeMap(t.alloc, &parser, {}, &root, S.decodeRoot, 
        \\{
        \\    name: 'project',
        \\    list: [
        \\        { field: 1 },
        \\        { field: 2 },
        \\    ],
        \\    map: {
        \\        1: 'foo',
        \\        2: 'bar',
        \\        3: "ba\"r",
        \\        4: """ba"r""",
        \\        5: """bar `bar`
        \\bar"""
        \\    }
        \\}
    );
    defer {
        t.alloc.free(root.list);
        t.alloc.free(root.name);
        for (root.map) |it| {
            t.alloc.free(it.val);
        }
        t.alloc.free(root.map);
    }

    try t.eqStr(root.name, "project");
    try t.eq(root.list[0].field, 1);
    try t.eq(root.list[1].field, 2);
    try t.eq(root.map.len, 5);
    try t.eq(root.map[0].id, 1);
    try t.eqStr(root.map[0].val, "foo");
    try t.eq(root.map[1].id, 2);
    try t.eqStr(root.map[1].val, "bar");
    try t.eq(root.map[2].id, 3);
    try t.eqStr(root.map[2].val, "ba\"r");
    try t.eq(root.map[3].id, 4);
    try t.eqStr(root.map[3].val, "ba\"r");
    try t.eq(root.map[4].id, 5);
    try t.eqStr(root.map[4].val, "bar `bar`\nbar");
}

// Same as std.mem.replace except we write to an ArrayList.
pub fn replaceIntoList(comptime T: type, input: []const T, needle: []const T, replacement: []const T, output: *std.ArrayList(T)) usize {
    // Clear the array list.
    output.clearRetainingCapacity();
    var i: usize = 0;
    var slide: usize = 0;
    var replacements: usize = 0;
    while (slide < input.len) {
        if (std.mem.indexOf(T, input[slide..], needle) == @as(usize, 0)) {
            output.appendSlice(replacement) catch unreachable;
            i += replacement.len;
            slide += needle.len;
            replacements += 1;
        } else {
            output.append(input[slide]) catch unreachable;
            i += 1;
            slide += 1;
        }
    }
    return replacements;
}