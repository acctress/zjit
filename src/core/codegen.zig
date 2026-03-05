const std = @import("std");
const IR = @import("ir.zig").IR;
const Register = @import("regs.zig").Register;
const Emitter = @import("emitter.zig").Emitter;
const builtin = @import("builtin");

pub const CodeGen = struct {
    allocator: std.mem.Allocator,
    emitter: *Emitter,

    pub fn init(allocator: std.mem.Allocator, emitter: *Emitter) CodeGen {
        return .{
            .allocator = allocator,
            .emitter = emitter,
        };
    }

    pub fn compile(self: *CodeGen, func: *IR.Function) !void {
        var register_map: std.AutoHashMap(u32, Register) = .init(self.allocator);
        defer register_map.deinit();

        const arg_registers = if (comptime builtin.os.tag == .windows)
            [_]Register{ .rcx, .rdx, .r8, .r9 }
        else
            [_]Register{ .rdi, .rsi, .rdx, .rcx };

        const free_registers = [_]Register{ .rax, .rcx, .rdx, .rbx, .r8, .r9 };

        for (func.blocks.items, 0..) |block, block_idx| {
            var current_reg: u32 = @intCast(block.parameters.len);

            for (block.parameters, 0..) |_, param_idx| {
                const val_idx = func.param_indices.items[block_idx][param_idx];
                try register_map.put(val_idx, arg_registers[param_idx]);
            }

            for (block.instructions.items) |inst| {
                switch (inst) {
                    .iconst => |constant| {
                        try register_map.put(current_reg, free_registers[current_reg]);
                        try self.emitter.mov_reg_imm64(register_map.get(current_reg).?, constant);
                        current_reg += 1;
                    },

                    .iadd => |add| {
                        try register_map.put(current_reg, free_registers[current_reg]);
                        try self.emitter.mov_reg_reg(register_map.get(current_reg).?, register_map.get(add.lhs).?);
                        try self.emitter.add_reg_reg(register_map.get(current_reg).?, register_map.get(add.rhs).?);
                        current_reg += 1;
                    },

                    .ret => |r| {
                        try self.emitter.mov_reg_reg(.rax, register_map.get(r.value).?);
                        try self.emitter.ret();
                    },
                }
            }
        }
    }
};
