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

        const free_registers = [_]Register{ .rax, .rbx, .r10, .r11, .r12, .r13, .r14, .r15 };

        var labels: std.ArrayList(usize) = .empty;
        defer labels.deinit(self.allocator);

        for (func.blocks.items) |_| {
            try labels.append(self.allocator, try self.emitter.label());
        }

        var next_val: u32 = 0;
        var free_reg_idx: u32 = 0;
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
                        free_reg_idx += 1;
                        next_val += 1;
                    },

                    .iadd => |add| {
                        try register_map.put(next_val, free_registers[next_val]);
                        try self.emitter.mov_reg_reg(register_map.get(next_val).?, register_map.get(add.lhs).?);
                        try self.emitter.add_reg_reg(register_map.get(next_val).?, register_map.get(add.rhs).?);
                        free_reg_idx += 1;
                        next_val += 1;
                    },

                    .isub => |sub| {
                        try register_map.put(next_val, free_registers[next_val]);
                        try self.emitter.mov_reg_reg(register_map.get(next_val).?, register_map.get(sub.lhs).?);
                        try self.emitter.sub_reg_reg(register_map.get(next_val).?, register_map.get(sub.rhs).?);
                        next_val += 1;
                    },

                    .imul => |mul| {
                        try register_map.put(next_val, free_registers[next_val]);
                        try self.emitter.mov_reg_reg(register_map.get(next_val).?, register_map.get(mul.lhs).?);
                        try self.emitter.imul_reg_reg(register_map.get(next_val).?, register_map.get(mul.rhs).?);
                        next_val += 1;
                    },

                    .icmp => |icmp| {
                        try register_map.put(next_val, free_registers[next_val]);
                        try self.emitter.cmp_reg_reg(register_map.get(icmp.lhs).?, register_map.get(icmp.rhs).?);
                        try self.emitter.setcc(icmp.kind, .rax);
                        try self.emitter.movzx_reg_reg8(.rax, .rax);
                        try self.emitter.mov_reg_reg(register_map.get(next_val).?, .rax);
                        next_val += 1;
                    },

                    .brif => |brif| {
                        // don't want to corrupt registers if the condition isn't true or false
                        // so jump to the correct label depending on condition to avoid this
                        const true_guard = try self.emitter.label();
                        const false_guard = try self.emitter.label();

                        try self.emitter.cmp_reg_imm32(register_map.get(brif.condition).?, 0);
                        try self.emitter.jnz(true_guard);

                        try self.emitter.bind(false_guard);
                        if (brif.false_args.len > 0) {
                            for (brif.false_args, 0..) |arg, arg_idx| {
                                // a really simple move of the jmp arg regs to block arg regs.
                                const target_reg = arg_registers[arg_idx];
                                const src_reg = register_map.get(arg).?;
                                try self.emitter.mov_reg_reg(target_reg, src_reg);
                            }
                        }
                        try self.emitter.jmp(labels.items[brif.false_block]);

                        try self.emitter.bind(true_guard);
                        if (brif.true_args.len > 0) {
                            for (brif.true_args, 0..) |arg, arg_idx| {
                                // a really simple move of the jmp arg regs to block arg regs.
                                const target_reg = arg_registers[arg_idx];
                                const src_reg = register_map.get(arg).?;
                                try self.emitter.mov_reg_reg(target_reg, src_reg);
                            }
                        }
                        try self.emitter.jmp(labels.items[brif.true_block]);
                    },

                    .jmp => |jmp| {
                        for (jmp.args, 0..) |arg, arg_idx| {
                            // a really simple move of the jmp arg regs to block arg regs.
                            const target_reg = arg_registers[arg_idx];
                            const src_reg = register_map.get(arg).?;
                            try self.emitter.mov_reg_reg(target_reg, src_reg);
                        }

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
