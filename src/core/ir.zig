const std = @import("std");
const SetCCKind = @import("emitter.zig").SetCCKind;

pub const IR = struct {
    pub const Value = u32;

    pub const no_args: []const Value = &[_]Value{};

    pub const Type = enum {
        i64,
        i32,
        bool,
        ptr,
    };

    pub const no_types: []const Type = &[_]Type{};

    pub const InstType = enum {
        iconst,
        iadd,
        isub,
        imul,
        icmp,
        brif,
        jmp,
        ret,
    };

    pub const Inst = union(InstType) {
        iconst: i64,
        iadd: struct { lhs: Value, rhs: Value },
        isub: struct { lhs: Value, rhs: Value },
        imul: struct { lhs: Value, rhs: Value },
        icmp: struct { kind: SetCCKind, lhs: Value, rhs: Value },
        brif: struct {
            condition: Value,
            true_block: usize,
            false_block: usize,
            true_args: []const Value,
            false_args: []const Value,
        },
        jmp: struct { to_block: usize, args: []const Value },
        ret: struct { value: Value },
    };

    pub const BasicBlock = struct {
        parameters: []const Type,
        instructions: std.ArrayList(Inst),
    };

    pub const Block = struct {
        params: []u32,

        pub fn param(self: Block, idx: usize) u32 {
            return self.params[idx];
        }
    };

    pub const Function = struct {
        allocator: std.mem.Allocator,
        blocks: std.ArrayList(BasicBlock),
        types: std.ArrayList(Type),
        param_indices: std.ArrayList([]u32),

        pub fn init(allocator: std.mem.Allocator) !Function {
            return .{
                .allocator = allocator,
                .blocks = .empty,
                .types = .empty,
                .param_indices = .empty,
            };
        }

        pub fn deinit(self: *Function) void {
            for (self.blocks.items) |b| {
                b.instructions.deinit(self.allocator);
            }

            for (self.param_indices.items) |i| {
                self.allocator.free(i);
            }

            self.blocks.deinit(self.allocator);
            self.types.deinit(self.allocator);
        }

        pub fn createBlock(self: *Function, params: []const Type) !Block {
            const block: BasicBlock = .{
                .instructions = .empty,
                .parameters = params,
            };

            var indices: std.ArrayList(u32) = .empty;
            for (block.parameters) |t| {
                try self.types.append(self.allocator, t);
                try indices.append(self.allocator, @as(u32, @intCast(self.types.items.len - 1)));
            }

            const owned = try indices.toOwnedSlice(self.allocator);
            try self.param_indices.append(self.allocator, owned);

            try self.blocks.append(self.allocator, block);

            return .{
                .params = owned,
            };
        }

        pub fn iconst(self: *Function, imm: i64) !u32 {
            const inst: Inst = .{ .iconst = imm };

            try self.blocks.items[
                self.blocks.items.len - 1
            ].instructions.append(self.allocator, inst);

            try self.types.append(self.allocator, .i64);

            return @intCast(self.types.items.len - 1);
        }

        pub fn iadd(self: *Function, lhs: Value, rhs: Value) !u32 {
            const inst: Inst = .{ .iadd = .{
                .lhs = lhs,
                .rhs = rhs,
            } };

            try self.blocks.items[
                self.blocks.items.len - 1
            ].instructions.append(self.allocator, inst);

            try self.types.append(self.allocator, .i64);

            return @intCast(self.types.items.len - 1);
        }

        pub fn isub(self: *Function, lhs: Value, rhs: Value) !u32 {
            const inst: Inst = .{ .isub = .{
                .lhs = lhs,
                .rhs = rhs,
            } };

            try self.blocks.items[
                self.blocks.items.len - 1
            ].instructions.append(self.allocator, inst);

            try self.types.append(self.allocator, .i64);

            return @intCast(self.types.items.len - 1);
        }

        pub fn imul(self: *Function, lhs: Value, rhs: Value) !u32 {
            const inst: Inst = .{ .imul = .{
                .lhs = lhs,
                .rhs = rhs,
            } };

            try self.blocks.items[
                self.blocks.items.len - 1
            ].instructions.append(self.allocator, inst);

            try self.types.append(self.allocator, .i64);

            return @intCast(self.types.items.len - 1);
        }

        pub fn icmp(self: *Function, kind: SetCCKind, lhs: Value, rhs: Value) !u32 {
            const inst: Inst = .{ .icmp = .{
                .kind = kind,
                .lhs = lhs,
                .rhs = rhs,
            } };

            try self.blocks.items[
                self.blocks.items.len - 1
            ].instructions.append(self.allocator, inst);

            try self.types.append(self.allocator, .bool);

            return @intCast(self.types.items.len - 1);
        }

        pub fn brif(
            self: *Function,
            condition: Value,
            true_block: usize,
            false_block: usize,
            true_args: []const Value,
            false_args: []const Value,
        ) !void {
            const inst: Inst = .{
                .brif = .{
                    .condition = condition,
                    .true_block = true_block,
                    .false_block = false_block,
                    .true_args = true_args,
                    .false_args = false_args,
                },
            };

            try self.blocks.items[
                self.blocks.items.len - 1
            ].instructions.append(self.allocator, inst);
        }

        pub fn jmp(self: *Function, to_block: usize, args: []const Value) !void {
            const inst: Inst = .{ .jmp = .{
                .to_block = to_block,
                .args = args,
            } };

            try self.blocks.items[
                self.blocks.items.len - 1
            ].instructions.append(self.allocator, inst);
        }

        pub fn ret(self: *Function, value: Value) !void {
            const inst: Inst = .{ .ret = .{ .value = value } };

            try self.blocks.items[
                self.blocks.items.len - 1
            ].instructions.append(self.allocator, inst);
        }
    };
};
