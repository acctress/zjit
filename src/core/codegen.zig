const std = @import("std");
const IR = @import("ir.zig").IR;
const Register = @import("regs.zig").Register;
const Emitter = @import("emitter.zig").Emitter;

pub const CodeGen = struct {
    emitter: *Emitter,

    pub fn init(emitter: *Emitter) CodeGen {
        return .{
            .emitter = emitter,
        };
    }

    pub fn compile(self: *CodeGen, func: *IR.Function) !void {
        const register_map = [_]Register{ .rax, .rcx, .rdx, .rbx, .rsi, .rdi, .r8, .r9 };
        var current_reg: u32 = 0;

        for (func.blocks.items) |block| {
            for (block.instructions.items) |inst| {
                switch (inst) {
                    .iconst => |constant| {
                        try self.emitter.mov_reg_imm64(register_map[current_reg], constant);
                        current_reg += 1;
                    },

                    .iadd => |add| {
                        try self.emitter.mov_reg_reg(register_map[current_reg], register_map[add.lhs]);
                        try self.emitter.add_reg_reg(register_map[current_reg], register_map[add.rhs]);
                        current_reg += 1;
                    },

                    .ret => |r| {
                        try self.emitter.mov_reg_reg(.rax, register_map[r.value]);
                        try self.emitter.ret();
                    },
                }
            }
        }
    }
};
