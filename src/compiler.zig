const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const stdx = @import("stdx");
const t = stdx.testing;
const cy = @import("cyber.zig");
const cc = @import("capi.zig");
const rt = cy.rt;
const fmt = @import("fmt.zig");
const v = fmt.v;
const vmc = @import("vm_c.zig");
const sema = cy.sema;
const bt = cy.types.BuiltinTypes;
const core_mod = @import("builtins/builtins.zig");
const cy_mod = @import("builtins/cy.zig");
const math_mod = @import("builtins/math.zig");
const llvm_gen = @import("llvm_gen.zig");
const cgen = @import("cgen.zig");
const bcgen = @import("bc_gen.zig");
const jitgen = @import("jit/gen.zig");
const assm = @import("jit/assembler.zig");
const A64 = @import("jit/a64.zig");
const bindings = cy.bindings;
const module = cy.module;

const log = cy.log.scoped(.compiler);

const f64NegOne = cy.Value.initF64(-1);
const f64One = cy.Value.initF64(1);

const dumpCompileErrorStackTrace = !cy.isFreestanding and builtin.mode == .Debug and !cy.isWasm and true;

const Root = @This();

pub const Compiler = struct {
    alloc: std.mem.Allocator,
    vm: *cy.VM,
    buf: cy.ByteCodeBuffer,
    jitBuf: jitgen.CodeBuffer,

    reports: std.ArrayListUnmanaged(Report),
    
    /// Sema model resulting from the sema pass.
    sema: sema.Sema,

    /// Determines how modules are loaded.
    moduleLoader: cc.ModuleLoaderFn,

    /// Determines how module uris are resolved.
    moduleResolver: cc.ResolverFn,

    /// Compilation units for iteration.
    chunks: std.ArrayListUnmanaged(*cy.Chunk),

    /// Special chunks managed separately.
    ct_builtins_chunk: ?*cy.Chunk,

    /// Resolved URI to chunk.
    chunk_map: std.StringHashMapUnmanaged(*cy.Chunk),

    /// Key is either a *Sym or *Func.
    genSymMap: std.AutoHashMapUnmanaged(*anyopaque, bcgen.Sym),

    /// Imports are queued.
    import_tasks: std.ArrayListUnmanaged(ImportTask),

    config: cc.CompileConfig,

    /// Tracks whether an error was set from the API.
    hasApiError: bool,
    apiError: []const u8, // Duped so Cyber owns the msg.

    /// Whether core should be imported.
    importCore: bool = true,

    iteratorMID: vmc.MethodId = cy.NullId,
    nextMID: vmc.MethodId = cy.NullId,
    indexMID: vmc.MethodId = cy.NullId,
    setIndexMID: vmc.MethodId = cy.NullId,
    sliceMID: vmc.MethodId = cy.NullId,
    getMID: vmc.MethodId = cy.NullId,
    setMID: vmc.MethodId = cy.NullId,

    main_chunk: *cy.Chunk,

    global_sym: ?*cy.sym.UserVar,
    get_global: ?*cy.Func,

    /// Whether this is a subsequent compilation reusing the same state.
    cont: bool,

    chunk_start: u32,
    type_start: u32,

    pub fn init(self: *Compiler, vm: *cy.VM) !void {
        self.* = .{
            .alloc = vm.alloc,
            .vm = vm,
            .buf = try cy.ByteCodeBuffer.init(vm.alloc, vm),
            .jitBuf = jitgen.CodeBuffer.init(),
            .reports = .{},
            .sema = sema.Sema.init(vm.alloc, self),
            .moduleLoader = defaultModuleLoader,
            .moduleResolver = defaultModuleResolver,
            .chunks = .{},
            .ct_builtins_chunk = null,
            .chunk_map = .{},
            .genSymMap = .{},
            .import_tasks = .{},
            .config = cc.defaultCompileConfig(), 
            .hasApiError = false,
            .apiError = "",
            .main_chunk = undefined,
            .global_sym = null,
            .get_global = null,
            .cont = false,
            .chunk_start = 0,
            .type_start = 0,
        };
        try self.reinitPerRun();    
    }

    pub fn deinitModRetained(self: *Compiler) void {
        for (self.chunks.items) |chunk| {
            for (chunk.syms.items) |sym| {
                sym.deinitRetained(self.vm);
            }
        }
    }

    pub fn deinit(self: *Compiler, comptime reset: bool) void {
        self.clearReports();
        if (!reset) {
            self.reports.deinit(self.alloc);
        }

        if (reset) {
            self.buf.clear();
            self.jitBuf.clear();
        } else {
            self.buf.deinit();
            self.jitBuf.deinit(self.alloc);
        }

        // Retained vars are deinited first since they can depend on types/syms.
        self.deinitModRetained();

        // Free any remaining import tasks.
        for (self.import_tasks.items) |task| {
            self.alloc.free(task.resolved_spec);
        }

        for (self.chunks.items) |chunk| {
            log.tracev("Deinit chunk `{s}`", .{chunk.srcUri});
            if (chunk.onDestroy) |onDestroy| {
                onDestroy(@ptrCast(self.vm), cy.Sym.toC(@ptrCast(chunk.sym)));
            }
            chunk.deinit();
            self.alloc.destroy(chunk);
        }
        if (self.ct_builtins_chunk) |chunk| {
            chunk.deinit();
            self.alloc.destroy(chunk);
        }
        if (reset) {
            self.chunks.clearRetainingCapacity();
            self.chunk_map.clearRetainingCapacity();
            self.genSymMap.clearRetainingCapacity();
            self.import_tasks.clearRetainingCapacity();
        } else {
            self.chunks.deinit(self.alloc);
            self.chunk_map.deinit(self.alloc);
            self.genSymMap.deinit(self.alloc);
            self.import_tasks.deinit(self.alloc);
        }

        // Chunks depends on modules.
        self.sema.deinit(self.alloc, reset);

        self.alloc.free(self.apiError);
        self.apiError = "";
    }

    pub fn reinitPerRun(self: *Compiler) !void {
        self.clearReports();
    }

    pub fn clearReports(self: *Compiler) void {
        for (self.reports.items) |report| {
            report.deinit(self.alloc);
        }
        self.reports.clearRetainingCapacity();
    }

    pub fn newTypes(self: *Compiler) []cy.types.Type {
        return self.sema.types.items[self.type_start..];
    }

    pub fn newChunks(self: *Compiler) []*cy.Chunk {
        return self.chunks.items[self.chunk_start..];
    }

    pub fn compile(self: *Compiler, uri: []const u8, src: ?[]const u8, config: cc.CompileConfig) !CompileResult {
        self.chunk_start = @intCast(self.chunks.items.len);
        self.type_start = @intCast(self.sema.types.items.len);
        const res = self.compileInner(uri, src, config) catch |err| {
            if (dumpCompileErrorStackTrace and !cc.silent()) {
                std.debug.dumpStackTrace(@errorReturnTrace().?.*);
            }
            if (err == error.CompileError) {
                return err;
            }
            if (self.chunks.items.len > 0) {
                // Report other errors using the main chunk.
                return self.main_chunk.reportErrorFmt("Error: {}", &.{v(err)}, null);
            } else {
                try self.addReportFmt(.compile_err, "Error: {}", &.{v(err)}, null, null);
                return error.CompileError;
            }
        };

        // Update VM types view.
        self.vm.types = self.sema.types.items;

        // Successful.
        self.cont = true;
        return res;
    }

    /// Wrap compile so all errors can be handled in one place.
    fn compileInner(self: *Compiler, uri: []const u8, src_opt: ?[]const u8, config: cc.CompileConfig) !CompileResult {
        self.config = config;

        var r_uri: []const u8 = undefined;
        var src: []const u8 = undefined;
        if (src_opt) |src_temp| {
            src = try self.alloc.dupe(u8, src_temp);
            r_uri = try self.alloc.dupe(u8, uri);
        } else {
            var buf: [4096]u8 = undefined;
            const r_uri_temp = try resolveModuleUri(self, &buf, uri);
            r_uri = try self.alloc.dupe(u8, r_uri_temp);
            const res = (try loadModule(self, r_uri_temp)) orelse {
                try self.addReportFmt(.compile_err, "Failed to load module: {}", &.{v(r_uri_temp)}, null, null);
                return error.CompileError;
            };
            src = res.src[0..res.srcLen];
        }

        if (!self.cont) {
            try reserveCoreTypes(self);
            try loadCtBuiltins(self);
        }

        // TODO: Types and symbols should be loaded recursively for single-threaded.
        //       Separate into two passes one for types and function signatures, and
        //       another for function bodies.

        // Load core module first since the members are imported into each user module.
        var core_sym: *cy.sym.Chunk = undefined;
        if (self.importCore) {
            if (!self.cont) {
                const importCore = ImportTask{
                    .type = .nop,
                    .from = null,
                    .nodeId = cy.NullNode,
                    .resolved_spec = try self.alloc.dupe(u8, "core"),
                    .data = undefined,
                };
                try self.import_tasks.append(self.alloc, importCore);
                const core_chunk = performImportTask(self, importCore) catch |err| {
                    return err;
                };
                core_sym = core_chunk.sym;
                _ = self.import_tasks.orderedRemove(0);
                try createDynMethodIds(self);
            } else {
                core_sym = self.chunk_map.get("core").?.sym;
            }
        }

        // Main chunk.
        const nextId: u32 = @intCast(self.chunks.items.len);
        var mainChunk = try self.alloc.create(cy.Chunk);
        mainChunk.* = try cy.Chunk.init(self, nextId, r_uri, src);
        mainChunk.sym = try mainChunk.createChunkSym(r_uri);
        try self.chunks.append(self.alloc, mainChunk);
        try self.chunk_map.put(self.alloc, r_uri, mainChunk);

        if (self.cont) {
            // Use all *resolved* top level syms from previous main.
            // If a symbol wasn't resolved, it either failed during compilation or didn't end up getting used.
            var iter = self.main_chunk.sym.getMod().symMap.iterator();
            while (iter.next()) |e| {
                const name = e.key_ptr.*;
                const sym = e.value_ptr.*;

                const resolved = switch (sym.type) {
                    .object_t => sym.cast(.object_t).isResolved(),
                    .struct_t => sym.cast(.struct_t).isResolved(),
                    .func => sym.cast(.func).isResolved(),
                    else => true,
                };
                if (!resolved) {
                    continue;
                }

                const alias = try mainChunk.reserveUseAlias(@ptrCast(mainChunk.sym), name, cy.NullNode);
                if (sym.type == .use_alias) {
                    alias.sym = sym.cast(.use_alias).sym;
                } else {
                    alias.sym = sym;
                }
                alias.resolved = true;
            }

            if (self.main_chunk.use_global) {
                mainChunk.use_global = true;
            }
        }

        self.main_chunk = mainChunk;

        // All symbols are reserved by loading all modules and looking at the declarations.
        try reserveSyms(self, core_sym);

        // Resolve symbols:
        // - Variable types are resolved.
        // - Function signatures are resolved.
        // - Type fields are resolved.
        try resolveSyms(self);

        // Pass through type syms.
        for (self.newTypes()) |*type_e| {
            if (type_e.sym.getMod().?.getSym("$get") != null) {
                type_e.has_get_method = true;
            }
            if (type_e.sym.getMod().?.getSym("$set") != null) {
                type_e.has_set_method = true;
            }
            if (type_e.sym.getMod().?.getSym("$initPair") != null) {
                type_e.has_init_pair_method = true;
            }
        }

        // Compute type sizes after type fields have been resolved.
        // try computeTypeSizesRec(self);

        // Perform sema on static initializers.
        log.tracev("Perform init sema.", .{});
        for (self.newChunks()) |chunk| {
            // First stmt is root at index 0.
            _ = try chunk.ir.pushEmptyStmt2(chunk.alloc, .root, chunk.parserAstRootId, false);
            try chunk.ir.pushStmtBlock2(chunk.alloc, chunk.rootStmtBlock);

            chunk.initializerVisited = false;
            chunk.initializerVisiting = false;
            if (chunk.hasStaticInit) {
                try performChunkInitSema(self, chunk);
            }

            chunk.rootStmtBlock = chunk.ir.popStmtBlock();
        }

        // Perform sema on all chunks.
        log.tracev("Perform sema.", .{});
        for (self.newChunks()) |chunk| {
            performChunkSema(self, chunk) catch |err| {
                if (err == error.CompileError) {
                    return err;
                } else {
                    // Wrap all other errors as a CompileError.
                    return chunk.reportErrorFmt("error.{}", &.{v(err)}, chunk.curNodeId);
                }
                return err;
            };
        }

        // Perform deferred sema.
        for (self.newChunks()) |chunk| {
            try chunk.ir.pushStmtBlock2(chunk.alloc, chunk.rootStmtBlock);
            for (chunk.variantFuncSyms.items) |func| {
                if (func.type != .userFunc) {
                    continue;
                }
                if (func.isMethod) {
                    try sema.methodDecl(chunk, func);
                } else {
                    try sema.funcDecl(chunk, func);
                }
            }
            chunk.rootStmtBlock = chunk.ir.popStmtBlock();
            // No more statements are added to the chunks root, so update bodyHead.
            chunk.ir.setStmtData(0, .root, .{ .bodyHead = chunk.rootStmtBlock.first });
        }

        if (!config.skip_codegen) {
            log.tracev("Perform codegen.", .{});

            switch (self.config.backend) {
                cc.BackendJIT => {
                    if (cy.isWasm) return error.Unsupported;
                    try jitgen.gen(self);
                    return .{ .jit = .{
                        .mainStackSize = self.buf.mainStackSize,
                        .buf = self.jitBuf,
                    }};
                },
                cc.BackendTCC, cc.BackendCC => {
                    if (cy.isWasm or !cy.hasCLI) return error.Unsupported;
                    const res = try cgen.gen(self);
                    return .{ .aot = res };
                },
                cc.BackendLLVM => {
                    // try llvm_gen.genNativeBinary(self);
                    return error.TODO;
                },
                cc.BackendVM => {
                    try bcgen.genAll(self);
                    return .{
                        .vm = self.buf,
                    };
                },
                else => return error.Unsupported,
            }
            log.tracev("Done. Perform codegen.", .{});
        }

        return CompileResult{ .vm = undefined };
    }

    pub fn addReportFmt(self: *Compiler, report_t: ReportType, format: []const u8, args: []const fmt.FmtValue, chunk: ?cy.ChunkId, loc: ?cy.NodeId) !void {
        const msg = try fmt.allocFormat(self.alloc, format, args);
        try self.addReportConsume(report_t, msg, chunk, loc);
    }

    /// Assumes `msg` is heap allocated.
    pub fn addReportConsume(self: *Compiler, report_t: ReportType, msg: []const u8, chunk: ?cy.ChunkId, loc: ?cy.NodeId) !void {
        try self.reports.append(self.alloc, .{
            .type = report_t,
            .chunk = chunk orelse cy.NullId,
            .loc = loc orelse cy.NullNode,
            .msg = msg,
        });
    }

    pub fn addReport(self: *Compiler, report_t: ReportType, msg: []const u8, chunk: ?cy.ChunkId, loc: ?cy.NodeId) !void {
        const dupe = try self.alloc.dupe(u8, msg);
        try self.addReportConsume(report_t, dupe, chunk, loc);
    }
};

const ReportType = enum(u8) {
    token_err,
    parse_err,
    compile_err,
};

pub const Report = struct {
    type: ReportType,
    msg: []const u8,

    /// If NullId, then the report comes from an aggregate step.
    chunk: cy.ChunkId,

    /// srcPos if token_err or parse_err
    //  nodeId if compile_err
    /// If NullId, then the report does not have a location.
    loc: u32,

    pub fn deinit(self: Report, alloc: std.mem.Allocator) void {
        alloc.free(self.msg);
    }
};

pub const AotCompileResult = struct {
    exePath: [:0]const u8,

    pub fn deinit(self: AotCompileResult, alloc: std.mem.Allocator) void {
        alloc.free(self.exePath);
    }
};

/// Tokenize and parse.
/// Parser pass collects static declaration info.
fn performChunkParse(self: *Compiler, chunk: *cy.Chunk) !void {
    _ = self;
    var tt = cy.debug.timer();

    const S = struct {
        fn parserReport(ctx: *anyopaque, format: []const u8, args: []const cy.fmt.FmtValue, pos: u32) anyerror {
            const c: *cy.Chunk = @ptrCast(@alignCast(ctx));
            try c.compiler.addReportFmt(.parse_err, format, args, c.id, pos);
            return error.ParseError;
        }

        fn tokenizerReport(ctx: *anyopaque, format: []const u8, args: []const cy.fmt.FmtValue, pos: u32) anyerror!void {
            const c: *cy.Chunk = @ptrCast(@alignCast(ctx));
            try c.compiler.addReportFmt(.token_err, format, args, c.id, pos);
            return error.TokenError;
        }
    };

    chunk.parser.reportFn = S.parserReport;
    chunk.parser.tokenizerReportFn = S.tokenizerReport;
    chunk.parser.ctx = chunk;

    const res = try chunk.parser.parse(chunk.src, .{});
    tt.endPrint("parse");
    // Update buffer pointers so success/error paths can access them.
    chunk.updateAstView(res.ast);
    if (res.has_error) {
        return error.CompileError;
    }
    chunk.parserAstRootId = res.root_id;
}

/// Sema pass.
/// Symbol resolving, type checking, and builds the model for codegen.
fn performChunkSema(self: *Compiler, chunk: *cy.Chunk) !void {
    try chunk.ir.pushStmtBlock2(chunk.alloc, chunk.rootStmtBlock);

    if (chunk == self.main_chunk) {
        _ = try sema.semaMainBlock(self, chunk);
    }
    // Top level declarations only.
    try performChunkSemaDecls(chunk);

    chunk.rootStmtBlock = chunk.ir.popStmtBlock();
}

fn performChunkSemaDecls(c: *cy.Chunk) !void {
    // Iterate funcs with explicit index since lambdas could be appended.
    var i: u32 = 0;
    var num_funcs: u32 = @intCast(c.funcs.items.len);
    while (i < num_funcs) : (i += 1) {
        const func = c.funcs.items[i];
        switch (func.type) {
            .userFunc => {
                // Skip already emitted functions such as `$init`.
                if (func.emitted) {
                    continue;
                }
                log.tracev("sema func: {s}", .{func.name()});
                if (func.isMethod) {
                    try sema.methodDecl(c, func);
                } else {
                    try sema.funcDecl(c, func);
                }
            },
            else => {},
        }
    }
}

/// Sema on static initializers.
fn performChunkInitSema(self: *Compiler, c: *cy.Chunk) !void {
    log.tracev("Perform init sema. {} {s}", .{c.id, c.srcUri});

    const funcSigId = try c.sema.ensureFuncSig(&.{}, bt.Void);

    const decl = try c.parser.ast.pushNode(self.alloc, .funcDecl, cy.NullId);
    const header = try c.parser.ast.pushNode(self.alloc, .funcHeader, cy.NullNode);
    const name = try c.parser.ast.genSpanNode(self.alloc, .ident, "$init", null);
    c.parser.ast.setNodeData(header, .{ .funcHeader = .{
        .name = name,
        .paramHead = cy.NullNode,
        .nparams = 0,
    }});
    c.parser.ast.setNodeData(decl, .{ .func = .{
        .header = @intCast(header),
        .bodyHead = cy.NullNode,
        .sig_t = .func,
        .hidden = true,
    }});
    c.updateAstView(c.parser.ast.view());

    const func = try c.reserveUserFunc(@ptrCast(c.sym), "$init", decl, false);
    try c.resolveUserFunc(func, funcSigId);

    _ = try sema.pushFuncProc(c, func);

    for (c.syms.items) |sym| {
        switch (sym.type) {
            .userVar => {
                const user_var = sym.cast(.userVar);
                try sema.staticDecl(c, sym, user_var.declId);
            },
            else => {},
        }
    }

    // Pop unordered stmts list.
    _ = c.ir.popStmtBlock();
    // Create a new stmt list.
    try c.ir.pushStmtBlock(c.alloc);

    // Reorder local declarations in DFS order by patching next stmt IR.
    for (c.syms.items) |sym| {
        switch (sym.type) {
            .userVar => {
                const info = c.symInitInfos.getPtr(sym).?;
                try appendSymInitIrDFS(c, sym, info, cy.NullNode);
            },
            else => {},
        }
    }

    try sema.popFuncBlock(c);
    func.emitted = true;
}

fn appendSymInitIrDFS(c: *cy.Chunk, sym: *cy.Sym, info: *cy.chunk.SymInitInfo, refNodeId: cy.NodeId) !void {
    if (info.visited) {
        return;
    }
    if (info.visiting) {
        return c.reportErrorFmt("Referencing `{}` creates a circular dependency in the module.", &.{v(sym.name())}, refNodeId);
    }
    info.visiting = true;

    const deps = c.symInitDeps.items[info.depStart..info.depEnd];
    if (deps.len > 0) {
        for (deps) |dep| {
            if (c.symInitInfos.getPtr(dep.sym)) |depInfo| {
                try appendSymInitIrDFS(c, dep.sym, depInfo, dep.refNodeId);
            }
        }
    }

    // Append stmt in the correct order.
    c.ir.appendToParent(info.irStart);
    // Reset this stmt's next or it can end up creating a cycle list.
    c.ir.setStmtNext(info.irStart, cy.NullId);

    info.visited = true;
}

fn completeImportTask(self: *Compiler, task: ImportTask, res: *cy.Chunk) !void {
    switch (task.type) {
        .nop => {},
        .module_alias => {
            task.data.module_alias.sym.sym = @ptrCast(res.sym);
        },
        .use_alias => {
            const c = task.from.?;

            const node = c.ast.node(task.nodeId);
            const name_n = c.ast.node(node.data.import_stmt.name);
            if (name_n.type() == .all) {
                try c.use_alls.append(self.alloc, @ptrCast(res.sym));
            } else {
                task.data.use_alias.sym.sym = @ptrCast(res.sym);
                task.data.use_alias.sym.resolved = true;
            }
        },
    }
}

fn loadModule(self: *Compiler, r_uri: []const u8) !?cc.ModuleLoaderResult {
    // Initialize defaults.
    var res: cc.ModuleLoaderResult = .{
        .src = "",
        .srcLen = 0,
        .funcLoader = null,
        .varLoader = null,
        .typeLoader = null,
        .onTypeLoad = null,
        .onLoad = null,
        .onDestroy = null,
        .onReceipt = null,
    };

    self.hasApiError = false;
    log.tracev("Invoke module loader: {s}", .{r_uri});

    if (self.moduleLoader.?(@ptrCast(self.vm), cc.toStr(r_uri), &res)) {
        const src_temp = res.src[0..res.srcLen];
        const src = try self.alloc.dupe(u8, src_temp);
        if (res.onReceipt) |onReceipt| {
            onReceipt(@ptrCast(self.vm), &res);
        }
        res.src = src.ptr;
        return res;
    } else {
        return null;
    }
}

fn performImportTask(self: *Compiler, task: ImportTask) !*cy.Chunk {
    // Check cache if module src was already obtained from the module loader.
    const cache = try self.chunk_map.getOrPut(self.alloc, task.resolved_spec);
    if (cache.found_existing) {
        try completeImportTask(self, task, cache.value_ptr.*);
        self.alloc.free(task.resolved_spec);
        return cache.value_ptr.*;
    }

    var res = (try loadModule(self, task.resolved_spec)) orelse {
        if (task.from) |from| {
            if (task.nodeId == cy.NullNode) {
                if (self.hasApiError) {
                    return from.reportError(self.apiError, null);
                } else {
                    return from.reportErrorFmt("Failed to load module: {}", &.{v(task.resolved_spec)}, null);
                }
            } else {
                const stmt = from.ast.node(task.nodeId);
                if (self.hasApiError) {
                    return from.reportErrorFmt(self.apiError, &.{}, stmt.data.import_stmt.spec);
                } else {
                    return from.reportErrorFmt("Failed to load module: {}", &.{v(task.resolved_spec)}, stmt.data.import_stmt.spec);
                }
            }
        } else {
            try self.addReportFmt(.compile_err, "Failed to load module: {}", &.{v(task.resolved_spec)}, null, null);
            return error.CompileError;
        }
    };
    const src = res.src[0..res.srcLen];

    // Push another chunk.
    const newChunkId: u32 = @intCast(self.chunks.items.len);

    // uri is already duped.
    var newChunk = try self.alloc.create(cy.Chunk);

    newChunk.* = try cy.Chunk.init(self, newChunkId, task.resolved_spec, src);
    newChunk.sym = try newChunk.createChunkSym(task.resolved_spec);
    newChunk.funcLoader = res.funcLoader;
    newChunk.varLoader = res.varLoader;
    newChunk.typeLoader = res.typeLoader;
    newChunk.onTypeLoad = res.onTypeLoad;
    newChunk.onLoad = res.onLoad;
    newChunk.srcOwned = true;
    newChunk.onDestroy = res.onDestroy;

    try self.chunks.append(self.alloc, newChunk);
    
    try completeImportTask(self, task, newChunk);
    cache.value_ptr.* = newChunk;

    return newChunk;
}

fn reserveSyms(self: *Compiler, core_sym: *cy.sym.Chunk) !void{
    log.tracev("Reserve symbols.", .{});

    var id: u32 = self.chunk_start;
    while (true) {
        while (id < self.chunks.items.len) : (id += 1) {
            const chunk = self.chunks.items[id];
            log.tracev("chunk parse: {}", .{chunk.id});
            try performChunkParse(self, chunk);

            if (self.importCore) {
                // Import all from core module into local namespace.
                try chunk.use_alls.append(self.alloc, @ptrCast(core_sym));
            }

            // Process static declarations.
            for (chunk.parser.staticDecls.items) |*decl| {
                log.tracev("reserve: {s}", .{try chunk.ast.declNamePath(decl.nodeId)});
                switch (decl.declT) {
                    .use_import => {
                        try sema.declareUseImport(chunk, decl.nodeId);
                    },
                    .use_alias => {
                        _ = try sema.reserveUseAlias(chunk, decl.nodeId);
                    },
                    .struct_t => {
                        const sym = try sema.reserveStruct(chunk, decl.nodeId);
                        const node = chunk.ast.node(decl.nodeId);
                        var cur: cy.NodeId = node.data.objectDecl.funcHead;
                        while (cur != cy.NullNode) {
                            _ = try sema.reserveImplicitMethod(chunk, @ptrCast(sym), cur);
                            cur = chunk.ast.node(cur).next();
                        }
                    },
                    .object => {
                        const sym = try sema.reserveObjectType(chunk, decl.nodeId);
                        const node = chunk.ast.node(decl.nodeId);
                        var cur: cy.NodeId = node.data.objectDecl.funcHead;
                        while (cur != cy.NullNode) {
                            _ = try sema.reserveImplicitMethod(chunk, @ptrCast(sym), cur);
                            cur = chunk.ast.node(cur).next();
                        }
                    },
                    .table_t => {
                        const sym = try sema.reserveObjectType(chunk, decl.nodeId);
                        try sema.reserveTableMethods(chunk, @ptrCast(sym));

                        const node = chunk.ast.node(decl.nodeId);
                        var cur: cy.NodeId = node.data.objectDecl.funcHead;
                        while (cur != cy.NullNode) {
                            _ = try sema.reserveImplicitMethod(chunk, @ptrCast(sym), cur);
                            cur = chunk.ast.node(cur).next();
                        }
                    },
                    .enum_t => {
                        _ = try sema.reserveEnum(chunk, decl.nodeId);
                    },
                    .typeAlias => {
                        _ = try sema.reserveTypeAlias(chunk, decl.nodeId);
                    },
                    .distinct_t => {
                        const sym = try sema.reserveDistinctType(chunk, decl.nodeId);
                        const node = chunk.ast.node(decl.nodeId);
                        var cur: cy.NodeId = node.data.distinct_decl.func_head;
                        while (cur != cy.NullNode) {
                            _ = try sema.reserveImplicitMethod(chunk, @ptrCast(sym), cur);
                            cur = chunk.ast.node(cur).next();
                        }
                    },
                    .template => {
                        _ = try sema.declareTemplate(chunk, decl.nodeId);
                    },
                    .variable => {
                        const sym = try sema.reserveVar(chunk, decl.nodeId);
                        if (sym.type == .userVar) {
                            chunk.hasStaticInit = true;
                        }
                    },
                    .func => {
                        _ = try sema.reserveUserFunc(chunk, decl.nodeId);
                    },
                    .funcInit => {
                        _ = try sema.reserveHostFunc(chunk, decl.nodeId);
                    },
                }
            }

            if (chunk.onTypeLoad) |onTypeLoad| {
                onTypeLoad(@ptrCast(self.vm), chunk.sym.sym().toC());
            }

            if (id == 0) {
                // Extract special syms. Assumes chunks[0] is the builtins chunk.
                const core = self.chunks.items[0].sym.getMod();
                self.sema.option_tmpl = core.getSym("Option").?.cast(.template);
                self.sema.table_type = core.getSym("Table").?.cast(.object_t);
            }
        }

        // Check for import tasks.
        for (self.import_tasks.items, 0..) |task, i| {
            _ = performImportTask(self, task) catch |err| {
                try self.import_tasks.replaceRange(self.alloc, 0, i, &.{});
                return err;
            };
        }
        self.import_tasks.clearRetainingCapacity();

        if (id == self.chunks.items.len) {
            // No more chunks were added from import tasks.
            break;
        }
    }
}

fn loadCtBuiltins(self: *Compiler) !void {
    const bc = try self.alloc.create(cy.Chunk);
    const ct_builtins_uri = try self.alloc.dupe(u8, "ct");
    bc.* = try cy.Chunk.init(self, cy.NullId, ct_builtins_uri, "");
    bc.sym = try bc.createChunkSym(ct_builtins_uri);
    self.ct_builtins_chunk = bc;

    _ = try bc.declareBoolType(@ptrCast(bc.sym), "bool_t", null, cy.NullNode);
    _ = try bc.declareIntType(@ptrCast(bc.sym), "int64_t", 64, null, cy.NullNode);
    _ = try bc.declareFloatType(@ptrCast(bc.sym), "float64_t", 64, null, cy.NullNode);
}

fn reserveCoreTypes(self: *Compiler) !void {
    log.tracev("Reserve core types", .{});

    const type_ids = &[_]cy.TypeId{
        // Incomplete type.
        bt.Void,

        // Primitives.
        bt.Boolean,
        bt.Error,
        bt.Placeholder1,
        bt.Placeholder2,
        bt.Placeholder3,
        bt.Symbol,
        bt.Integer,
        bt.Float,

        // Unions.
        bt.Dynamic,
        bt.Any,

        // VM specific types.
        bt.Type,

        // Object types.
        bt.Tuple,
        bt.List,
        bt.ListIter,
        bt.Map,
        bt.MapIter,
        bt.Closure,
        bt.Lambda,
        bt.HostFunc,
        bt.ExternFunc,
        bt.String,
        bt.Array,
        bt.Fiber,
        bt.Box,
        bt.TccState,
        bt.Pointer,
        bt.MetaType,
        bt.Range,
        bt.Table,
    };

    for (type_ids) |type_id| {
        const id = try self.sema.pushType();
        std.debug.assert(id == type_id);
    }

    std.debug.assert(self.sema.types.items.len == cy.types.BuiltinEnd);
}

fn createDynMethodIds(self: *Compiler) !void {
    self.indexMID = try self.vm.ensureMethod("$index");
    self.setIndexMID = try self.vm.ensureMethod("$setIndex");
    self.sliceMID = try self.vm.ensureMethod("$slice");
    self.iteratorMID = try self.vm.ensureMethod("iterator");
    self.nextMID = try self.vm.ensureMethod("next");
    self.getMID = try self.vm.ensureMethod("$get");
    self.setMID = try self.vm.ensureMethod("$set");
}

// fn computeTypeSizesRec(self: *VMcompiler) !void {
//     log.tracev("Compute type sizes.", .{});
//     for (self.chunks.items) |chunk| {
//         // Process static declarations.
//         for (chunk.parser.staticDecls.items) |decl| {
//             switch (decl.declT) {
//                 // .struct_t => {
//                 // },
//                 .object => {
//                     const object_t = decl.data.sym.cast(.object_t);
//                     if (object_t.rt_size == cy.NullId) {
//                         try computeTypeSize(object_t);
//                     }
//                 },
//                 // .enum_t => {
//                 // },
//                 else => {},
//             }
//         }

//         if (chunk.onLoad) |onLoad| {
//             onLoad(@ptrCast(self.vm), cc.ApiModule{ .sym = @ptrCast(chunk.sym) });
//         }
//     }
// }

// fn computeTypeSize(object_t: *cy.sym.ObjectType) !void {
//     var size: u32 = 0;
//     for (object_t.getFields()) |field| {
//         if (field.type == )
//         _ = field;
//     }
//     object_t.rt_size = size;
// }

fn resolveSyms(self: *Compiler) !void {
    log.tracev("Resolve syms.", .{});
    for (self.newChunks()) |chunk| {
        // Iterate funcs with explicit index since unnamed types could be appended.
        var i: u32 = 0;
        while (i < chunk.syms.items.len) : (i += 1) {
            const sym = chunk.syms.items[i];
            log.tracev("resolve: {s}", .{sym.name()});
            switch (sym.type) {
                .userVar => {
                    try sema.resolveUserVar(chunk, @ptrCast(sym));
                },
                .hostVar => {
                    try sema.resolveHostVar(chunk, @ptrCast(sym));
                },
                .func => {},
                .struct_t => {
                    const struct_t = sym.cast(.struct_t);
                    try sema.resolveObjectFields(chunk, sym, struct_t.declId);
                },
                .object_t => {
                    const object_t = sym.cast(.object_t);
                    const decl = chunk.ast.node(object_t.declId);
                    if (decl.type() == .table_decl) {
                        try sema.resolveTableFields(chunk, @ptrCast(sym));
                        try sema.resolveTableMethods(chunk, @ptrCast(sym));
                    } else {
                        try sema.resolveObjectFields(chunk, sym, object_t.declId);
                    }
                },
                .enum_t => {
                    const enum_t = sym.cast(.enum_t);
                    try sema.declareEnumMembers(chunk, @ptrCast(sym), enum_t.decl);
                },
                .distinct_t => {
                    _ = try sema.resolveDistinctType(chunk, @ptrCast(sym));
                },
                .use_alias => {
                    const use_alias = sym.cast(.use_alias);
                    const decl = chunk.ast.node(use_alias.decl);
                    if (decl.type() == .use_alias) {
                        try sema.resolveUseAlias(chunk, @ptrCast(sym));
                    }
                },
                .typeAlias => {
                    try sema.resolveTypeAlias(chunk, @ptrCast(sym));
                },
                else => {},
            }
        }

        for (chunk.funcs.items) |func| {
            try sema.resolveFunc(chunk, func);
        }

        if (chunk.onLoad) |onLoad| {
            onLoad(@ptrCast(self.vm), chunk.sym.sym().toC());
        }
    }
}

pub const CompileResult = union {
    vm: cy.ByteCodeBuffer,
    jit: struct {
        mainStackSize: u32,
        buf: jitgen.CodeBuffer,
    },
    aot: AotCompileResult,
};

const VarInfo = struct {
    hasStaticType: bool,
};

const Load = struct {
    pc: u32,
    tempOffset: u8,
};

// Same as std.mem.replace except writes to an ArrayList. Final result is also known to be at most the size of the original.
pub fn replaceIntoShorterList(comptime T: type, input: []const T, needle: []const T, replacement: []const T, output: *std.ArrayListUnmanaged(T), alloc: std.mem.Allocator) !usize {
    // Known upper bound.
    try output.resize(alloc, input.len);
    var i: usize = 0;
    var slide: usize = 0;
    var replacements: usize = 0;
    while (slide < input.len) {
        if (std.mem.indexOf(T, input[slide..], needle) == @as(usize, 0)) {
            std.mem.copy(u8, output.items[i..i+replacement.len], replacement);
            i += replacement.len;
            slide += needle.len;
            replacements += 1;
        } else {
            output.items[i] = input[slide];
            i += 1;
            slide += 1;
        }
    }
    output.items.len = i;
    return replacements;
}

const unexpected = cy.fatal;

const ImportTaskType = enum(u8) {
    nop,
    use_alias,
    module_alias,
};

pub const ImportTask = struct {
    type: ImportTaskType,
    from: ?*cy.Chunk,
    nodeId: cy.NodeId,
    resolved_spec: []const u8,
    data: union {
        module_alias: struct {
            sym: *cy.sym.ModuleAlias,
        },
        use_alias: struct {
            sym: *cy.sym.UseAlias,
        },
    },
};

pub fn initModuleCompat(comptime name: []const u8, comptime initFn: fn (vm: *Compiler, modId: cy.ModuleId) anyerror!void) cy.ModuleLoaderFunc {
    return struct {
        fn initCompat(vm: *cy.UserVM, modId: cy.ModuleId) bool {
            initFn(vm.internal().compiler, modId) catch |err| {
                log.tracev("Init module `{s}` failed: {}", .{name, err});
                return false;
            };
            return true;
        }
    }.initCompat;
}

pub fn defaultModuleResolver(_: ?*cc.VM, params: cc.ResolverParams) callconv(.C) bool {
    params.resUri.* = params.uri.ptr;
    params.resUriLen.* = params.uri.len;
    return true;
}

pub fn defaultModuleLoader(vm_: ?*cc.VM, spec: cc.Str, out_: [*c]cc.ModuleLoaderResult) callconv(.C) bool {
    const out: *cc.ModuleLoaderResult = out_;
    const name = cc.fromStr(spec);
    if (std.mem.eql(u8, name, "core")) {
        const vm: *cy.VM = @ptrCast(@alignCast(vm_));
        const aot = cy.isAot(vm.compiler.config.backend);
        out.* = .{
            .src = if (aot) core_mod.Src else core_mod.VmSrc,
            .srcLen = if (aot) core_mod.Src.len else core_mod.VmSrc.len,
            .funcLoader = core_mod.funcLoader,
            .typeLoader = if (aot) core_mod.typeLoader else core_mod.vmTypeLoader,
            .onLoad = core_mod.onLoad,
            .onReceipt = null,
            .varLoader = null,
            .onTypeLoad = null,
            .onDestroy = null,
        };
        return true;
    } else if (std.mem.eql(u8, name, "math")) {
        out.* = .{
            .src = math_mod.Src,
            .srcLen = math_mod.Src.len,
            .funcLoader = math_mod.funcLoader,
            .varLoader = math_mod.varLoader,
            .typeLoader = null,
            .onLoad = null,
            .onReceipt = null,
            .onTypeLoad = null,
            .onDestroy = null,
        };
        return true;
    } else if (std.mem.eql(u8, name, "cy")) {
        out.* = .{
            .src = cy_mod.Src,
            .srcLen = cy_mod.Src.len,
            .funcLoader = cy_mod.funcLoader,
            .varLoader = null,
            .typeLoader = null,
            .onLoad = null,
            .onReceipt = null,
            .onTypeLoad = null,
            .onDestroy = null,
        };
        return true;
    }
    return false;
}

pub fn resolveModuleUriFrom(self: *cy.Chunk, buf: []u8, uri: []const u8, nodeId: cy.NodeId) ![]const u8 {
    self.compiler.hasApiError = false;

    var r_uri: [*]const u8 = undefined;
    var r_uri_len: usize = undefined;
    const params: cc.ResolverParams = .{
        .chunkId = self.id,
        .curUri = cc.toStr(self.srcUri),
        .uri = cc.toStr(uri),
        .buf = buf.ptr,
        .bufLen = buf.len,
        .resUri = @ptrCast(&r_uri),
        .resUriLen = &r_uri_len,
    };
    if (!self.compiler.moduleResolver.?(@ptrCast(self.compiler.vm), params)) {
        if (self.compiler.hasApiError) {
            return self.reportErrorFmt(self.compiler.apiError, &.{}, nodeId);
        } else {
            return self.reportErrorFmt("Failed to resolve module.", &.{}, nodeId);
        }
    }
    return r_uri[0..r_uri_len];
}

pub fn resolveModuleUri(self: *cy.Compiler, buf: []u8, uri: []const u8) ![]const u8 {
    self.hasApiError = false;

    var r_uri: [*]const u8 = undefined;
    var r_uri_len: usize = undefined;
    const params: cc.ResolverParams = .{
        .chunkId = cy.NullId,
        .curUri = cc.NullStr,
        .uri = cc.toStr(uri),
        .buf = buf.ptr,
        .bufLen = buf.len,
        .resUri = @ptrCast(&r_uri),
        .resUriLen = &r_uri_len,
    };
    if (!self.moduleResolver.?(@ptrCast(self.vm), params)) {
        if (self.hasApiError) {
            try self.addReport(.compile_err, self.apiError, null, null);
            return error.CompileError;
        } else {
            try self.addReport(.compile_err, "Failed to resolve module.", null, null);
            return error.CompileError;
        }
    }
    return r_uri[0..r_uri_len];
}

test "vm compiler internals." {
    try t.eq(@offsetOf(Compiler, "buf"), @offsetOf(vmc.Compiler, "buf"));
    try t.eq(@offsetOf(Compiler, "reports"), @offsetOf(vmc.Compiler, "reports"));
    try t.eq(@offsetOf(Compiler, "sema"), @offsetOf(vmc.Compiler, "sema"));
}