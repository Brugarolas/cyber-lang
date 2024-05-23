const std = @import("std");
const builtin = @import("builtin");
const stdx = @import("stdx");
const t = stdx.testing;
const cy = @import("cyber.zig");
const log = cy.log.scoped(.ast);

pub const NodeType = enum(u7) {
    // To allow non optional nodes.
    // Can be used to simplify code by accepting *Node only instead of ?*Node.
    null,

    accessExpr,
    all,
    arrayLit,
    array_expr,
    array_init,
    assignStmt,
    attribute,
    await_expr,
    binExpr,
    binLit,
    breakStmt,
    caseBlock,
    callExpr,
    castExpr,
    catchStmt,
    coinit,
    comptimeExpr,
    comptimeStmt,
    continueStmt,
    coresume,
    coyield,
    custom_decl,
    decLit,
    distinct_decl,
    dot_lit,
    else_block,
    enumDecl,
    enumMember,
    error_lit,
    expandOpt,
    exprStmt,
    falseLit,
    forIterStmt,
    forRangeStmt,
    floatLit,
    funcDecl,
    funcParam,
    group,
    hexLit,
    ident,
    if_expr,
    if_stmt,
    if_unwrap_stmt,
    import_stmt,
    keyValue,
    label_decl,
    lambda_expr, 
    lambda_multi,
    localDecl,
    name_path,
    namedArg,
    noneLit,
    objectDecl,
    objectField,
    octLit,
    opAssignStmt,
    passStmt,
    range,
    raw_string_lit,
    recordLit,
    record_expr,
    returnExprStmt,
    returnStmt,
    root,
    runeLit,
    semaSym,
    seqDestructure,
    specialization,
    staticDecl,
    stringLit,
    stringTemplate,
    structDecl,
    switchExpr,
    switchStmt,
    symbol_lit,
    table_decl,
    throwExpr,
    trueLit,
    tryExpr,
    tryStmt,
    typeAliasDecl,
    template,
    unary_expr,
    unwrap,
    unwrap_or,
    use_alias,
    void,
    whileCondStmt,
    whileInfStmt,
    whileOptStmt,
};

pub const AttributeType = enum(u8) {
    host,
};

const ExpandOpt = struct {
    param: *Node align(8),
    pos: u32,
};

const ExprStmt = struct {
    child: *Node align(8),
    isLastRootStmt: bool = false, 
};

const ReturnExprStmt = struct {
    child: *Node align(8),
    pos: u32,
};

pub const ImportStmt = struct {
    name: *Node align(8),
    spec: ?*Node,
    pos: u32,
};

pub const Token = struct {
    pos: u32 align(8),
};

// idents and literals.
pub const Span = struct {
    // This can be different from Node.srcPos if the literal was generated.
    pos: u32 align(8),
    len: u16,
    srcGen: bool,
};

pub const NamePath = struct {
    path: []*Node align(8),
};

const NamedArg = struct {
    name_pos: u32 align(8),
    name_len: u32,
    arg: *Node,
};

pub const TryStmt = struct {
    stmts: []*Node align(8),
    catchStmt: *CatchStmt,
    pos: u32,
};

const CatchStmt = struct {
    errorVar: ?*Node align(8),
    stmts: []*Node,
    pos: u32,
};

const TryExpr = struct {
    expr: *Node align(8),
    catchExpr: ?*Node,
    pos: u32,
};

const CastExpr = struct {
    expr: *Node align(8),
    typeSpec: *Node,
};

const AssignStmt = struct {
    left: *Node align(8),
    right: *Node,
};

pub const BinExpr = struct {
    left: *Node align(8),
    right: *Node,
    op: BinaryExprOp,
    op_pos: u32,
};

const OpAssignStmt = struct {
    left: *Node align(8),
    right: *Node,
    op: BinaryExprOp,
    assign_pos: u32,
};

pub const CaseBlock = struct {
    // conds.len == 0 if `else` case.
    conds: []*Node align(8),
    capture: ?*Node,
    stmts: []*Node,
    bodyIsExpr: bool,
    pos: u32,
};

pub const SwitchBlock = struct {
    expr: *Node align(8),
    cases: []*CaseBlock,
    pos: u32,
};

pub const Attribute = struct {
    type: AttributeType align(8),
    value: ?*Node,
    pos: u32,
};

const ThrowExpr = struct {
    child: *Node align(8),
    pos: u32,
};

const Group = struct {
    child: *Node align(8),
    pos: u32,
};

const Coresume = struct {
    child: *Node align(8),
    pos: u32,
};

const Coinit = struct {
    child: *CallExpr align(8),
    pos: u32,
};

pub const IfStmt = struct {
    cond: *Node align(8),
    stmts: []const *Node,
    else_blocks: []*ElseBlock,
    pos: u32,
};

pub const ElseBlock = struct {
    // for else ifs only.
    cond: ?*Node align(8),
    stmts: []const *Node,
    pos: u32,
};

pub const IfUnwrapStmt = struct {
    opt: *Node align(8),
    unwrap: *Node,
    stmts: []const *Node,
    else_blocks: []*ElseBlock,
    pos: u32,
};

const AccessExpr = struct {
    left: *Node align(8),
    right: *Node,
};

const Unwrap = struct {
    opt: *Node align(8),
};

const UnwrapOr = struct {
    opt: *Node align(8),
    default: *Node,
};

pub const CallExpr = struct {
    callee: *Node align(8),
    args: []*Node,
    hasNamedArg: bool,
};

pub const ArrayLit = struct {
    args: []*Node align(8),
    pos: u32,
};

const ArrayExpr = struct {
    left: *Node align(8),
    args: []*Node,
};

const ArrayInit = struct {
    left: *Node align(8),
    args: []*Node,
};

const RecordExpr = struct {
    left: *Node align(8),
    record: *RecordLit,
};

pub const RecordLit = struct {
    args: []*KeyValue align(8),
    pos: u32,
};

const Unary = struct {
    child: *Node align(8),
    op: UnaryOp,
};

pub const Root = struct {
    stmts: []const *Node align(8),
};

pub const KeyValue = struct {
    key: *Node align(8),
    value: *Node,
};

pub const ComptimeExpr = struct {
    child: *Node align(8),
};

const ComptimeStmt = struct {
    expr: *Node align(8),
    pos: u32,
};

pub const LambdaExpr = struct {
    params: []const *FuncParam align(8),
    // For single expr lambda, `stmts.ptr` refers to the node.
    stmts: []const *Node,
    sig_t: FuncSigType,
    ret: ?*Node,
    pos: u32,
};

pub const FuncDecl = struct {
    name: *Node align(8),
    attrs: []*Attribute,
    params: []const *FuncParam,
    ret: ?*Node,
    hidden: bool,
    stmts: []*Node,
    sig_t: FuncSigType,
    pos: u32,
};

pub const FuncParam = struct {
    name_pos: u32 align(8),
    name_len: u32,
    typeSpec: ?*Node,
};

pub const UseAlias = struct {
    name: *Node align(8),
    target: *Node,
    pos: u32,
};

pub const TypeAliasDecl = struct {
    name: *Node align(8),
    typeSpec: *Node,
    hidden: bool,
    pos: u32,
};

pub const CustomDecl = struct {
    name: *Node align(8),
    attrs: []*Attribute,
    hidden: bool,
    funcs: []*FuncDecl,
    pos: u32,
};

pub const DistinctDecl = struct {
    name: *Node align(8),
    attrs: []*Attribute,
    target: *Node,
    hidden: bool,
    funcs: []*FuncDecl,
    pos: u32,
};

pub const Field = struct {
    name: *Node align(8),
    typeSpec: *Node,
    hidden: bool,
};

pub const TableDecl = struct {
    name: *Node align(8),
    attrs: []*Attribute,
    fields: []*Node,
    funcs: []*FuncDecl,
    pos: u32,
};

pub const ObjectDecl = struct {
    /// If unnamed, this points to the *Sym.
    name: ?*Node align(8),
    attrs: []*Attribute,
    fields: []*Field,
    funcs: []*FuncDecl,
    unnamed: bool,
    pos: u32,
};

pub const StaticVarDecl = struct {
    name: *Node align(8),
    attrs: []*Attribute,
    typeSpec: ?*Node,
    right: ?*Node,
    typed: bool,
    // Declared with `.` prefix.
    root: bool,
    hidden: bool,
    pos: u32,
};

pub const VarDecl = struct {
    name: *Node align(8),
    typeSpec: ?*Node,
    right: *Node,
    typed: bool,
    pos: u32
};

pub const EnumMember = struct {
    name: *Node align(8),
    typeSpec: ?*Node,
    pos: u32,
};

pub const EnumDecl = struct {
    name: *Node align(8),
    members: []*EnumMember,
    isChoiceType: bool,
    hidden: bool,
    pos: u32,
};

const WhileInfStmt = struct {
    stmts: []*Node align(8),
    pos: u32,
};

const WhileCondStmt = struct {
    cond: *Node align(8),
    stmts: []const *Node,
    pos: u32,
};

const WhileOptStmt = struct {
    opt: *Node align(8),
    capture: *Node,
    stmts: []const *Node,
    pos: u32,
};

const ForRangeStmt = struct {
    start: *Node align(8),
    end: *Node,
    each: ?*Node,
    increment: bool,
    stmts: []*Node,
    pos: u32,
};

const ForIterStmt = struct {
    iterable: *Node align(8),
    each: ?*Node,
    count: ?*Node,
    stmts: []const *Node,
    pos: u32,
};

const SemaSym = struct {
    sym: *cy.Sym align(8),
};

pub const SeqDestructure = struct {
    args: []*Node align(8),
    pos: u32,
};

const Specialization = struct {
    args: []*Node align(8),
    decl: *Node,
    pos: u32,
};

pub const TemplateDecl = struct {
    params: []*FuncParam align(8),
    decl: *Node,
    hidden: bool,
    pos: u32,
};

const Range = struct {
    start: ?*Node align(8),
    end: ?*Node,
    inc: bool,
    pos: u32,
};

const IfExpr = struct {
    cond: *Node align(8),
    body: *Node,
    else_expr: *Node,
    pos: u32,
};

pub const StringTemplate = struct {
    // Begins with a string lit and alternates between expr and string lits.
    parts: []*Node align(8),
};

const FuncSigType = enum(u8) {
    func,
    let,
    infer,
};

fn NodeData(comptime node_t: NodeType) type {
    return switch (node_t) {
        .null           => Node,
        .accessExpr     => AccessExpr,
        .all            => Token,
        .arrayLit       => ArrayLit,
        .array_expr     => ArrayExpr,
        .array_init     => ArrayInit,
        .assignStmt     => AssignStmt,
        .attribute      => Attribute,
        .await_expr     => void,
        .binExpr        => BinExpr,
        .binLit         => Span,
        .breakStmt      => Token,
        .caseBlock      => CaseBlock,
        .callExpr       => CallExpr,
        .castExpr       => CastExpr,
        .catchStmt      => CatchStmt,
        .coinit         => Coinit,
        .comptimeExpr   => ComptimeExpr,
        .comptimeStmt   => ComptimeStmt,
        .continueStmt   => Token,
        .coresume       => Coresume,
        .coyield        => Token,
        .custom_decl    => CustomDecl,
        .decLit         => Span,
        .distinct_decl  => DistinctDecl,
        .dot_lit        => Span,
        .else_block     => ElseBlock,
        .enumDecl       => EnumDecl,
        .enumMember     => EnumMember,
        .error_lit      => Span,
        .expandOpt      => ExpandOpt,
        .exprStmt       => ExprStmt,
        .falseLit       => Token,
        .forIterStmt    => ForIterStmt,
        .forRangeStmt   => ForRangeStmt,
        .floatLit       => Span,
        .funcDecl       => FuncDecl,
        .funcParam      => FuncParam,
        .group          => Group,
        .hexLit         => Span,
        .ident          => Span,
        .if_expr        => IfExpr,
        .if_stmt        => IfStmt,
        .if_unwrap_stmt => IfUnwrapStmt,
        .import_stmt    => ImportStmt,
        .keyValue       => KeyValue,
        .label_decl     => void,
        .lambda_expr    => LambdaExpr,
        .lambda_multi   => LambdaExpr,
        .localDecl      => VarDecl,
        .name_path      => NamePath,
        .namedArg       => NamedArg,
        .noneLit        => Token,
        .objectDecl     => ObjectDecl,
        .objectField    => Field,
        .octLit         => Span,
        .opAssignStmt   => OpAssignStmt,
        .passStmt       => Token,
        .range          => Range,
        .raw_string_lit => Span,
        .recordLit      => RecordLit,
        .record_expr    => RecordExpr,
        .returnExprStmt => ReturnExprStmt,
        .returnStmt     => Token,
        .root           => Root,
        .runeLit        => Span,
        .semaSym        => SemaSym,
        .seqDestructure => SeqDestructure,
        .specialization => Specialization,
        .staticDecl     => StaticVarDecl,
        .stringLit      => Span,
        .stringTemplate => StringTemplate,
        .structDecl     => ObjectDecl,
        .switchExpr     => SwitchBlock,
        .switchStmt     => SwitchBlock,
        .symbol_lit     => Span,
        .table_decl     => TableDecl,
        .throwExpr      => ThrowExpr,
        .trueLit        => Token,
        .tryExpr        => TryExpr,
        .tryStmt        => TryStmt,
        .typeAliasDecl  => TypeAliasDecl,
        .template       => TemplateDecl,
        .unary_expr     => Unary,
        .unwrap         => Unwrap,
        .unwrap_or      => UnwrapOr,
        .use_alias      => UseAlias,
        .void           => Token,
        .whileCondStmt  => WhileCondStmt,
        .whileInfStmt   => WhileInfStmt,
        .whileOptStmt   => WhileOptStmt,
    };
}

const NodeHeader = packed struct {
    type: NodeType,
    is_block_expr: bool,
};

pub const Node = struct {
    dummy: u8 align(8) = undefined,

    pub fn @"type"(self: *Node) NodeType {
        return @as(*NodeHeader, @ptrFromInt(@intFromPtr(self) - 1)).*.type;
    }

    pub fn setType(self: *Node, node_t: NodeType) void {
        @as(*NodeHeader, @ptrFromInt(@intFromPtr(self) - 1)).*.type = node_t;
    }

    pub fn isBlockExpr(self: *Node) bool {
        return @as(*NodeHeader, @ptrFromInt(@intFromPtr(self) - 1)).*.is_block_expr;
    }

    pub fn setBlockExpr(self: *Node, is_block_expr: bool) void {
        @as(*NodeHeader, @ptrFromInt(@intFromPtr(self) - 1)).*.is_block_expr = is_block_expr;
    }

    pub fn cast(self: *Node, comptime node_t: NodeType) *NodeData(node_t) {
        if (cy.Trace) {
            if (self.type() != node_t) {
                std.debug.panic("Expected {}, found {}.", .{node_t, self.type()});
            }
        }
        return @ptrCast(@alignCast(self));
    }

    pub fn pos(self: *Node) u32 {
        return switch (self.type()) {
            .null           => cy.NullId,
            .all            => self.cast(.all).pos,
            .accessExpr     => self.cast(.accessExpr).left.pos(),
            .arrayLit       => self.cast(.arrayLit).pos,
            .array_expr     => self.cast(.array_expr).left.pos(),
            .array_init     => self.cast(.array_init).left.pos(),
            .assignStmt     => self.cast(.assignStmt).left.pos(),
            .attribute      => self.cast(.attribute).pos,
            .await_expr     => cy.NullId,
            .binExpr        => self.cast(.binExpr).op_pos,
            .binLit         => self.cast(.binLit).pos,
            .breakStmt      => self.cast(.breakStmt).pos,
            .callExpr       => self.cast(.callExpr).callee.pos(),
            .caseBlock      => self.cast(.caseBlock).pos,
            .castExpr       => self.cast(.castExpr).expr.pos(),
            .catchStmt      => self.cast(.catchStmt).pos,
            .coinit         => self.cast(.coinit).pos,
            .comptimeExpr   => self.cast(.comptimeExpr).child.pos()-1,
            .comptimeStmt   => self.cast(.comptimeStmt).pos,
            .continueStmt   => self.cast(.continueStmt).pos,
            .coresume       => self.cast(.coresume).pos,
            .coyield        => self.cast(.coyield).pos,
            .custom_decl    => self.cast(.custom_decl).pos,
            .decLit         => self.cast(.decLit).pos,
            .distinct_decl  => self.cast(.distinct_decl).pos,
            .dot_lit        => self.cast(.dot_lit).pos-1,
            .else_block     => self.cast(.else_block).pos,
            .enumDecl       => self.cast(.enumDecl).pos,
            .enumMember     => self.cast(.enumMember).name.pos(),
            .error_lit      => self.cast(.error_lit).pos-6,
            .expandOpt      => self.cast(.expandOpt).pos,
            .exprStmt       => self.cast(.exprStmt).child.pos(),
            .falseLit       => self.cast(.falseLit).pos,
            .floatLit       => self.cast(.floatLit).pos,
            .forIterStmt    => self.cast(.forIterStmt).pos,
            .forRangeStmt   => self.cast(.forRangeStmt).pos,
            .funcDecl       => self.cast(.funcDecl).pos,
            .funcParam      => self.cast(.funcParam).name_pos,
            .group          => self.cast(.group).pos,
            .hexLit         => self.cast(.hexLit).pos,
            .ident          => self.cast(.ident).pos,
            .if_expr        => self.cast(.if_expr).pos,
            .if_stmt        => self.cast(.if_stmt).pos,
            .if_unwrap_stmt => self.cast(.if_unwrap_stmt).pos,
            .keyValue       => self.cast(.keyValue).key.pos(),
            .import_stmt    => self.cast(.import_stmt).pos,
            .label_decl     => cy.NullId,
            .lambda_expr    => self.cast(.lambda_expr).pos,
            .lambda_multi   => self.cast(.lambda_multi).pos,
            .localDecl      => self.cast(.localDecl).pos,
            .name_path      => self.cast(.name_path).path[0].pos(),
            .namedArg       => self.cast(.namedArg).name_pos,
            .noneLit        => self.cast(.noneLit).pos,
            .objectDecl     => self.cast(.objectDecl).pos,
            .objectField    => self.cast(.objectField).name.pos(),
            .octLit         => self.cast(.octLit).pos,
            .opAssignStmt   => self.cast(.opAssignStmt).left.pos(),
            .passStmt       => self.cast(.passStmt).pos,
            .range          => self.cast(.range).pos,
            .raw_string_lit => self.cast(.raw_string_lit).pos,
            .record_expr    => self.cast(.record_expr).left.pos(),
            .recordLit      => self.cast(.recordLit).pos,
            .returnExprStmt => self.cast(.returnExprStmt).pos,
            .returnStmt     => self.cast(.returnStmt).pos,
            .root           => self.cast(.root).stmts[0].pos(),
            .runeLit        => self.cast(.runeLit).pos,
            .seqDestructure => self.cast(.seqDestructure).pos,
            .semaSym        => cy.NullId,
            .specialization => self.cast(.specialization).pos,
            .staticDecl     => self.cast(.staticDecl).pos,
            .stringLit      => self.cast(.stringLit).pos,
            .stringTemplate => self.cast(.stringTemplate).parts[0].pos(),
            .structDecl     => self.cast(.structDecl).pos,
            .switchExpr     => self.cast(.switchExpr).pos,
            .switchStmt     => self.cast(.switchStmt).pos,
            .symbol_lit     => self.cast(.symbol_lit).pos,
            .table_decl     => self.cast(.table_decl).pos,
            .template       => self.cast(.template).pos,
            .throwExpr      => self.cast(.throwExpr).pos,
            .trueLit        => self.cast(.trueLit).pos,
            .tryExpr        => self.cast(.tryExpr).pos,
            .tryStmt        => self.cast(.tryStmt).pos,
            .typeAliasDecl  => self.cast(.typeAliasDecl).pos,
            .unary_expr     => self.cast(.unary_expr).child.pos()-1,
            .unwrap         => self.cast(.unwrap).opt.pos(),
            .unwrap_or      => self.cast(.unwrap_or).opt.pos(),
            .use_alias      => self.cast(.use_alias).pos,
            .void           => self.cast(.void).pos,
            .whileInfStmt   => self.cast(.whileInfStmt).pos,
            .whileCondStmt  => self.cast(.whileCondStmt).pos,
            .whileOptStmt   => self.cast(.whileOptStmt).pos,
        };
    }
};

pub const BinaryExprOp = enum(u8) {
    index,
    plus,
    minus,
    star,
    caret,
    slash,
    percent,
    bitwiseAnd,
    bitwiseOr,
    bitwiseXor,
    bitwiseLeftShift,
    bitwiseRightShift,
    bang_equal,
    less,
    less_equal,
    greater,
    greater_equal,
    equal_equal,
    and_op,
    or_op,
    cast,
    range,
    reverse_range,
    dummy,

    pub fn name(self: BinaryExprOp) []const u8 {
        return switch (self) {
            .index => "$index",
            .less => "$infix<",
            .greater => "$infix>",
            .less_equal => "$infix<=",
            .greater_equal => "$infix>=",
            .minus => "$infix-",
            .plus => "$infix+",
            .star => "$infix*",
            .slash => "$infix/",
            .percent => "$infix%",
            .caret => "$infix^",
            .bitwiseAnd => "$infix&",
            .bitwiseOr => "$infix|",
            .bitwiseXor => "$infix||",
            .bitwiseLeftShift => "$infix<<",
            .bitwiseRightShift => "$infix>>",
            else => "unknown",
        };
    }
};

pub const UnaryOp = enum(u8) {
    minus,
    not,
    bitwiseNot,
    dummy,

    pub fn name(self: UnaryOp) []const u8 {
        return switch (self) {
            .minus => "$prefix-",
            .not => "$prefix!",
            .bitwiseNot => "$prefix~",
            else => "unknown",
        };
    }
};

test "ast internals." {
    try t.eq(std.enums.values(NodeType).len, 91);
    try t.eq(@sizeOf(NodeHeader), 1);
}

pub const Ast = struct {
    node_alloc_handle: std.heap.ArenaAllocator,
    node_alloc: std.mem.Allocator,
    root: ?*Root,
    null_node: *Node,
    src: []const u8,

    /// Generated source literals from templates or CTE.
    srcGen: std.ArrayListUnmanaged(u8),

    /// Heap generated strings, stable pointers unlike `srcGen`.
    /// Used for:
    /// - Unnamed struct identifiers.
    /// - Unescaped strings.
    strs: std.ArrayListUnmanaged([]const u8),

    /// Optionally parsed by tokenizer.
    comments: std.ArrayListUnmanaged(cy.IndexSlice(u32)),

    pub fn init(self: *Ast, alloc: std.mem.Allocator, src: []const u8) !void {
        self.* = .{
            .node_alloc_handle = std.heap.ArenaAllocator.init(alloc),
            .node_alloc = undefined,
            .root = null,
            .null_node = undefined,
            .src = src,
            .srcGen = .{},
            .strs = .{},
            .comments = .{},
        };
        self.node_alloc = self.node_alloc_handle.allocator();
        try self.clearNodes();
    }

    pub fn deinit(self: *Ast, alloc: std.mem.Allocator) void {
        self.node_alloc_handle.deinit();
        self.srcGen.deinit(alloc);
        for (self.strs.items) |str| {
            alloc.free(str);
        }
        self.strs.deinit(alloc);
        self.comments.deinit(alloc);
    }

    pub fn clearNodes(self: *Ast) !void {
        _ = self.node_alloc_handle.reset(.retain_capacity);
        self.null_node = try self.newEmptyNode(.null);
    }

    pub fn view(self: *const Ast) AstView {
        return .{
            .root = self.root,
            .null_node = self.null_node,
            .src = self.src,
            .srcGen = self.srcGen.items,
        };
    }

    pub fn dupeNodes(self: *Ast, nodes: []const *Node) ![]*Node {
        return self.node_alloc.dupe(*Node, nodes);
    }

    pub fn newEmptyNode(self: *Ast, comptime node_t: NodeType) !*NodeData(node_t) {
        const Align = @alignOf(NodeData(node_t));
        const slice = try self.node_alloc.alignedAlloc(u8, Align, @sizeOf(NodeData(node_t)) + Align);
        @as(*NodeType, @ptrFromInt(@intFromPtr(slice.ptr) + Align - 1)).* = node_t;
        return @ptrFromInt(@intFromPtr(slice.ptr) + Align);
    }

    pub fn newNode(self: *Ast, comptime node_t: NodeType, data: NodeData(node_t)) !*NodeData(node_t) {
        const n = try self.newEmptyNode(node_t);
        n.* = data;
        return n;
    }

    pub fn newNodeErase(self: *Ast, comptime node_t: NodeType, data: NodeData(node_t)) !*Node {
        const n = try self.newEmptyNode(node_t);
        n.* = data;
        return @ptrCast(n);
    }

    pub fn genSpanNode(self: *Ast, alloc: std.mem.Allocator, comptime node_t: NodeType, str: []const u8) !*Span {
        const pos = self.srcGen.items.len;
        try self.srcGen.appendSlice(alloc, str);
        const span = try self.newSpanNode(node_t, pos, pos + str.len);
        span.srcGen = true;
        return span;
    }

    pub fn newSpanNode(self: *Ast, comptime node_t: NodeType, src_pos: usize, src_end: usize) !*Span {
        const span = try self.newEmptyNode(node_t);
        span.* = .{
            .pos = @intCast(src_pos),
            .len = @intCast(src_end-src_pos),
            .srcGen = false,
        };
        return span;
    }

    pub fn nodeString(self: Ast, n: *Node) []const u8 {
        const span: *Span = @ptrCast(@alignCast(n));
        if (span.srcGen) {
            return self.srcGen.items[span.pos..span.pos+span.len];
        } else {
            return self.src[span.pos..span.pos+span.len];
        }
    }
};

pub const AstView = struct {
    root: ?*Root,
    null_node: *Node,
    src: []const u8,
    srcGen: []const u8,

    /// Find the line/col in `src` at `pos`.
    /// Iterating tokens could be faster but it would still require counting new lines for skipped segments like comments, multiline strings.
    pub fn computeLinePos(self: AstView, pos: u32, outLine: *u32, outCol: *u32, outLineStart: *u32) void {
        var line: u32 = 0;
        var lineStart: u32 = 0;
        for (self.src, 0..) |ch, i| {
            if (i == pos) {
                break;
            }
            if (ch == '\n') {
                line += 1;
                lineStart = @intCast(i + 1);
            }
        }
        // This also handles the case where target pos is at the end of source.
        outLine.* = line;
        outCol.* = pos - lineStart;
        outLineStart.* = lineStart;
    }

    pub fn declNamePath(self: AstView, n: *Node) ![]const u8 {
        switch (n.type()) {
            .table_decl => {
                const object_decl = n.cast(.table_decl);
                return self.nodeString(object_decl.name);
            },
            .structDecl => {
                const object_decl = n.cast(.structDecl);
                if (object_decl.name) |name| {
                    return self.nodeString(name);
                } else return "";
            },
            .objectDecl => {
                const object_decl = n.cast(.objectDecl);
                if (object_decl.name) |name| {
                    return self.nodeString(name);
                } else return "";
            },
            .custom_decl => {
                const custom_decl = n.cast(.custom_decl);
                return self.nodeString(custom_decl.name);
            },
            .distinct_decl => {
                const distinct_decl = n.cast(.distinct_decl);
                return self.nodeString(distinct_decl.name);
            },
            .enumDecl => {
                const enum_decl = n.cast(.enumDecl);
                return self.nodeString(enum_decl.name);
            },
            .import_stmt => {
                const import_stmt = n.cast(.import_stmt);
                if (import_stmt.name.type() == .all) {
                    return "*";
                }
                return self.nodeString(import_stmt.name);
            },
            .use_alias => {
                return self.nodeString(n.cast(.use_alias).name);
            },
            .template => {
                return self.declNamePath(n.cast(.template).decl);
            },
            .specialization => {
                return self.declNamePath(n.cast(.specialization).decl);
            },
            .staticDecl => {
                return self.getNamePathInfo(n.cast(.staticDecl).name).name_path;
            },
            .typeAliasDecl => return self.nodeString(n.cast(.typeAliasDecl).name),
            .funcDecl => {
                return self.getNamePathInfo(n.cast(.funcDecl).name).name_path;
            },
            else => {
                log.tracev("{}", .{n.type()});
                return error.Unsupported;
            }
        }
    }

    pub fn funcParamName(self: AstView, param: *FuncParam) []const u8 {
        return self.src[param.name_pos..param.name_pos+param.name_len];
    }

    pub fn nodeString(self: AstView, n: *Node) []const u8 {
        const span: *Span = @ptrCast(@alignCast(n));
        if (span.srcGen) {
            return self.srcGen[span.pos..span.pos+span.len];
        } else {
            return self.src[span.pos..span.pos+span.len];
        }
    }

    pub fn nodeStringAndDelim(self: AstView, n: *Node) []const u8 {
        const span: *Span = @ptrCast(n);
        if (span.srcGen) {
            return self.srcGen[span.pos-1..span.pos+span.len+1];
        } else {
            return self.src[span.pos-1..span.pos+span.len+1];
        } 
    }

    pub fn isMethodDecl(self: AstView, decl: *FuncDecl) bool {
        if (decl.params.len == 0) {
            return false;
        }
        const param_name = self.funcParamName(decl.params[0]);
        return std.mem.eql(u8, param_name, "self");
    }

    pub fn getNamePathInfo(self: AstView, name: *Node) NamePathInfo {
        if (name.type() != .name_path) {
            const base = self.nodeString(name);
            return .{
                .name_path = base,
                .base_name = base,
                .base = name,
            };
        } else {
            const path = name.cast(.name_path).path;
            const last = path[path.len-1];
            const base = self.nodeString(last);

            var end = last.pos() + base.len;
            if (last.type() == .raw_string_lit) {
                end += 1;
            }
            return .{
                .name_path = self.src[name.pos()..end],
                .base_name = base,
                .base = last,
            };
        }
    }

    // Returns whether two lines are connected by a new line and optional indentation.
    pub fn isAdjacentLine(self: AstView, aEnd: u32, bStart: u32) bool {
        var i = aEnd;
        if (self.src[i] == '\r') {
            i += 1;
            if (self.src[i] != '\n') {
                return false;
            }
            i += 1;
        } else if (self.src[i] == '\n') {
            i += 1;
        } else {
            return false;
        }
        while (i < bStart) {
            if (self.src[i] != ' ' and self.src[i] != '\t') {
                return false;
            }
            i += 1;
        }
        return true;
    }
};

pub const NamePathInfo = struct {
    name_path: []const u8,
    base_name: []const u8,
    base: *Node,
};

const EncodeEvent = enum {
    preNode,
    postNode,
};

fn getUnOpStr(op: UnaryOp) []const u8 {
    return switch (op) {
        .minus => "-",
        .not => "!",
        .bitwiseNot => "~",
        .dummy => cy.unexpected(),
    };
}

fn getBinOpStr(op: BinaryExprOp) []const u8 {
    return switch (op) {
        .plus => "+",
        .minus => "-",
        .star => "*",
        .caret => "^",
        .slash => "/",
        .percent => "%",
        .bitwiseAnd => "&",
        .bitwiseOr => "|",
        .bitwiseXor => "||",
        .bitwiseLeftShift => "<<",
        .bitwiseRightShift => ">>",
        .bang_equal => "!=",
        .less => "<",
        .less_equal => "<=",
        .greater => ">",
        .greater_equal => ">=",
        .equal_equal => "==",
        .and_op => " and ",
        .or_op => " or ",
        .cast => "as",
        .range,
        .reverse_range,
        .index,
        .dummy => cy.unexpected(),
    };
}

/// The default encoder doesn't insert any formatting and is used to
/// provide a quick context summary next to generated code.
pub const Encoder = struct {
    ast: AstView,
    eventHandler: ?*const fn (Encoder, EncodeEvent, *Node) void = null,

    pub fn allocFmt(self: Encoder, alloc: std.mem.Allocator, node: ?*Node) ![]const u8 {
        if (node == null) {
            return "";
        }
        var buf: std.ArrayListUnmanaged(u8) = .{};
        try self.write(buf.writer(alloc), node.?);
        return buf.toOwnedSlice(alloc);
    }

    pub fn format(self: Encoder, node: ?*Node, buf: []u8) ![]const u8 {
        if (node == null) {
            return "";
        }
        var fbuf = std.io.fixedBufferStream(buf);
        try self.write(fbuf.writer(), node.?);
        return fbuf.getWritten();
    }

    pub fn write(self: Encoder, w: anytype, node: *Node) !void {
        switch (node.type()) {
            .funcDecl => {
                const decl = node.cast(.funcDecl);
                try w.writeAll("func ");
                try self.write(w, decl.name);
                try w.writeAll("(");
                if (decl.params.len > 0) {
                    try self.write(w, @ptrCast(decl.params[0]));
                    for (decl.params[1..]) |param| {
                        try w.writeAll(", ");
                        try self.write(w, @ptrCast(param));
                    }
                }
                try w.writeAll(")");
                if (decl.ret) |ret| {
                    try w.writeAll(" ");
                    try self.write(w, ret);
                }
                // node.data.func.bodyHead
            },
            .funcParam => {
                const param = node.cast(.funcParam);
                try w.writeAll(self.ast.funcParamName(param));
                if (param.typeSpec) |type_spec| {
                    try w.writeAll(" ");
                    try self.write(w, type_spec);
                }
            },
            .assignStmt => {
                const stmt = node.cast(.assignStmt);
                try self.write(w, stmt.left);
                try w.writeByte('=');
                try self.write(w, stmt.right);
            },
            .opAssignStmt => {
                const stmt = node.cast(.opAssignStmt);
                try self.write(w, stmt.left);
                try w.writeAll(getBinOpStr(stmt.op));
                try w.writeByte('=');
                try self.write(w, stmt.right);
            },
            .unary_expr => {
                const expr = node.cast(.unary_expr);
                try w.writeAll(getUnOpStr(expr.op));
                try self.write(w, expr.child);
            },
            .binExpr => {
                const expr = node.cast(.binExpr);
                try self.write(w, expr.left);
                try w.writeAll(getBinOpStr(expr.op));
                try self.write(w, expr.right);
            },
            .exprStmt => {
                try self.write(w, node.cast(.exprStmt).child);
            },
            .if_expr => {
                const expr = node.cast(.if_expr);
                try self.write(w, expr.cond);
                try w.writeAll("?");
                try self.write(w, expr.body);
                try w.writeAll(" else ");
                try self.write(w, expr.else_expr);
            },
            .caseBlock => {
                const block = node.cast(.caseBlock);
                if (block.conds.len == 0) {
                    try w.writeAll("else");
                } else {
                    try self.write(w, block.conds[0]);
                    for (block.conds[1..]) |cond| {
                        try w.writeByte(',');
                        try self.write(w, cond);
                    }
                }
                if (block.bodyIsExpr) {
                    try w.writeAll("=>");
                    try self.write(w, @ptrCast(@alignCast(block.stmts.ptr)));
                } else {
                    try w.writeAll(": ...");
                }
            },
            .noneLit => {
                try w.writeAll("none");
            },
            .falseLit => {
                try w.writeAll("false");
            },
            .trueLit => {
                try w.writeAll("true");
            },
            .dot_lit => {
                try w.writeAll(".");
                try w.writeAll(self.ast.nodeString(node));
            },
            .error_lit => {
                try w.writeAll("error.");
                try w.writeAll(self.ast.nodeString(node));
            },
            .symbol_lit => {
                try w.writeAll("symbol.");
                try w.writeAll(self.ast.nodeString(node));
            },
            .hexLit,
            .binLit,
            .octLit,
            .decLit => {
                try w.writeAll(self.ast.nodeString(node));
            },
            .ident => {
                try w.writeAll(self.ast.nodeString(node));
            },
            .raw_string_lit => {
                try w.writeAll(self.ast.nodeStringAndDelim(node));
            },
            .stringLit => {
                try w.writeAll(self.ast.nodeStringAndDelim(node));
            },
            .accessExpr => {
                const expr = node.cast(.accessExpr);
                try self.write(w, expr.left);
                try w.writeByte('.');
                try self.write(w, expr.right);
            },
            .group => {
                try w.writeByte('(');
                try self.write(w, node.cast(.group).child);
                try w.writeByte(')');
            },
            .range => {
                const expr = node.cast(.range);
                if (expr.start) |start| {
                    try self.write(w, start);
                }
                try w.writeAll("..");
                if (expr.end) |end| {
                    try self.write(w, end);
                }
            },
            .array_expr => {
                const expr = node.cast(.array_expr);
                try self.write(w, expr.left);
                try w.writeByte('[');
                if (expr.args.len > 0) {
                    try self.write(w, expr.args[0]);
                    for (expr.args[1..]) |arg| {
                        try w.writeAll(", ");
                        try self.write(w, arg);
                    }
                }
                try w.writeByte(']');
            },
            .record_expr => {
                const expr = node.cast(.record_expr);
                try self.write(w, expr.left);
                try self.write(w, @ptrCast(expr.record));
            },
            .throwExpr => {
                try w.writeAll("throw ");
                try self.write(w, node.cast(.throwExpr).child);
            },
            .callExpr => {
                const expr = node.cast(.callExpr);
                try self.write(w, expr.callee);

                try w.writeByte('(');
                if (expr.args.len > 0) {
                    try self.write(w, expr.args[0]);
                    for (expr.args[1..]) |arg| {
                        try w.writeAll(", ");
                        try self.write(w, arg);
                    }
                }
                try w.writeByte(')');
            },
            .tryExpr => {
                const expr = node.cast(.tryExpr);
                try w.writeAll("try ");
                try self.write(w, expr.expr);
                if (expr.catchExpr) |catch_expr| {
                    try w.writeAll(" catch ");
                    try self.write(w, catch_expr);
                }
            },
            .name_path => {
                const path = node.cast(.name_path).path;
                try self.write(w, path[0]);
                for (path[1..]) |part| {
                    try w.writeByte('.');
                    try self.write(w, part);
                }
            },
            .localDecl => {
                const local_decl = node.cast(.localDecl);
                if (local_decl.typed) {
                    try w.writeAll("var ");
                } else {
                    try w.writeAll("let ");
                }
                try self.write(w, local_decl.name);
                if (local_decl.typeSpec) |typeSpec| {
                    try w.writeByte(' ');
                    try self.write(w, typeSpec);
                }
                try w.writeByte('=');
                try self.write(w, local_decl.right);
            },
            .arrayLit => {
                const expr = node.cast(.arrayLit);
                try w.writeByte('[');
                if (expr.args.len > 0) {
                    try self.write(w, expr.args[0]);
                    for (expr.args[1..]) |arg| {
                        try w.writeAll(", ");
                        try self.write(w, arg);
                    }
                }
                try w.writeByte(']');
            },
            .recordLit => {
                try w.writeByte('{');
                try w.writeAll("...");
                try w.writeByte('}');
            },
            .expandOpt => {
                try w.writeByte('?');
                try self.write(w, node.cast(.expandOpt).param);
            },
            else => {
                try w.writeByte('<');
                try w.writeAll(@tagName(node.type()));
                try w.writeByte('>');
            },
        }
    }
};

// const VisitNode = packed struct {
//     nodeId: u31,
//     visited: bool,
// };

// pub const Visitor = struct {
//     alloc: std.mem.Allocator,
//     ast: AstView,
//     stack: std.ArrayListUnmanaged(VisitNode),

//     pub fn deinit(self: *Visitor) void {
//         self.stack.deinit(self.alloc);
//     }

//     pub fn visit(self: *Visitor, rootId: *Node,
//         comptime C: type, ctx: C, visitFn: *const fn(ctx: C, nodeId: NodeId, enter: bool) bool) !void {

//         self.stack.clearRetainingCapacity();
//         try self.pushNode(rootId);
//         while (self.stack.items.len > 0) {
//             const vnode = &self.stack.items[self.stack.items.len-1];
//             if (!vnode.visited) {
//                 if (visitFn(ctx, vnode.nodeId, true)) {
//                     vnode.visited = true;
//                     const node = self.ast.node(vnode.nodeId);
//                     switch (node.type()) {
//                         .objectField => {},
//                         .objectDecl => {
//                             try self.pushNodeList(node.data.objectDecl.funcHead, node.data.objectDecl.numFuncs);
//                             const header = self.ast.node(node.data.objectDecl.header);
//                             try self.pushNodeList(header.data.objectHeader.fieldHead, header.data.objectHeader.numFields);
//                         },
//                         else => {
//                             cy.rt.logZFmt("TODO: {}", .{node.type()});
//                             return error.TODO;
//                         }
//                     }
//                 } else {
//                     self.stack.items.len -= 1;
//                 }
//             } else {
//                 _ = visitFn(ctx, vnode.nodeId, false);
//                 self.stack.items.len -= 1;
//             }
//         }
//     }

//     fn pushNode(self: *Visitor, nodeId: NodeId) !void {
//         try self.stack.append(self.alloc, .{
//             .nodeId = @intCast(nodeId),
//             .visited = false,
//         });
//     }

//     fn pushNodeList(self: *Visitor, head: NodeId, size: u32) !void {
//         try self.stack.ensureUnusedCapacity(self.alloc, size);
//         self.stack.items.len += size;

//         var i: u32 = 0;
//         var cur = head;
//         while (cur != cy.NullNode) {
//             self.stack.items[self.stack.items.len-1-i] = .{
//                 .nodeId = @intCast(cur),
//                 .visited = false,
//             };
//             i += 1;
//             cur = self.ast.node(cur).next();
//         }
//     }
// };