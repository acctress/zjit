const std = @import("std");

pub const IR = struct {
    pub const Value = u32;

    pub const Type = enum {
        i64,
        i32,
        bool,
        ptr,
    };

    pub const InstType = enum {
        iconst,
        iadd,
        ret,
    };

    pub const Inst = union(InstType) {
        iconst: i64,
        iadd: struct { lhs: Value, rhs: Value },
        ret: struct { value: Value },
    };

    pub const BasicBlock = struct {
        instructions: std.ArrayList(Inst),
    };

    pub const Function = struct {
        allocator: std.mem.Allocator,
        blocks: std.ArrayList(BasicBlock),
        types: std.ArrayList(Type),

        pub fn init(allocator: std.mem.Allocator) !Function {
            return .{
                .allocator = allocator,
                .blocks = .empty,
                .types = .empty,
            };
        }

        pub fn deinit(self: *Function) void {
            for (self.blocks.items) |b| {
                b.instructions.deinit(self.allocator);
            }

            self.blocks.deinit(self.allocator);
            self.types.deinit(self.allocator);
        }

        pub fn createBlock(self: *Function) !void {
            const block: BasicBlock = .{ .instructions = .empty };
            try self.blocks.append(self.allocator, block);
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
            const inst: Inst = .{ .iadd = .{ .lhs = lhs, .rhs = rhs } };

            try self.blocks.items[
                self.blocks.items.len - 1
            ].instructions.append(self.allocator, inst);

            try self.types.append(self.allocator, .i64);

            return @intCast(self.types.items.len - 1);
        }

        pub fn ret(self: *Function, value: Value) !void {
            const inst: Inst = .{ .ret = .{ .value = value } };

            try self.blocks.items[
                self.blocks.items.len - 1
            ].instructions.append(self.allocator, inst);
        }
    };
};
