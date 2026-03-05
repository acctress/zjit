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

        var labels: std.ArrayList(usize) = .empty;
        defer labels.deinit(self.allocator);

        for (func.blocks.items) |_| {
            try labels.append(self.allocator, try self.emitter.label());
        }

        var next_val: u32 = 0;
        for (func.blocks.items, 0..) |block, block_idx| {
            next_val += @as(u32, @intCast(block.parameters.len));

            for (block.parameters, 0..) |_, param_idx| {
                const val_idx = func.param_indices.items[block_idx][param_idx];
                try register_map.put(val_idx, arg_registers[param_idx]);
            }

            try self.emitter.bind(labels.items[block_idx]);

            for (block.instructions.items) |inst| {
                switch (inst) {
                    .iconst => |constant| {
                        try register_map.put(next_val, free_registers[next_val]);
                        try self.emitter.mov_reg_imm64(register_map.get(next_val).?, constant);
                        next_val += 1;
                    },

                    .iadd => |add| {
                        try register_map.put(next_val, free_registers[next_val]);
                        try self.emitter.mov_reg_reg(register_map.get(next_val).?, register_map.get(add.lhs).?);
                        try self.emitter.add_reg_reg(register_map.get(next_val).?, register_map.get(add.rhs).?);
                        next_val += 1;
                    },

                    .brif => |brif| {
                        try self.emitter.cmp_reg_imm32(register_map.get(brif.condition).?, 0);
                        try self.emitter.jnz(labels.items[brif.true_block]);
                        try self.emitter.jmp(labels.items[brif.false_block]);
                    },

                    .jmp => |jmp| {
                        try self.emitter.jmp(labels.items[jmp.to_block]);
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
