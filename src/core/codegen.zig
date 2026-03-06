const std = @import("std");
const IR = @import("ir.zig").IR;
const Register = @import("regs.zig").Register;
const Emitter = @import("emitter.zig").Emitter;
const builtin = @import("builtin");
const RegAlloc = @import("regalloc.zig").RegAlloc;

pub const LiveRange = struct {
    expired: bool,
    value: u32,
    start: usize,
    end: usize,
};

const Allocation = struct {
    tag: enum { register, stack },
    data: union { reg: Register, slot: i32 },
};

pub const CodeGen = struct {
    allocator: std.mem.Allocator,
    emitter: *Emitter,

    pub fn init(allocator: std.mem.Allocator, emitter: *Emitter) CodeGen {
        return .{
            .allocator = allocator,
            .emitter = emitter,
        };
    }

    /// Compute the lifetimes of registers being used by have a range of usage, when it reaches it's end it's register is usable, cleaned up.
    fn computeLiveRanges(self: *CodeGen, func: *const IR.Function) !std.AutoHashMap(u32, LiveRange) {
        var live_ranges: std.AutoHashMap(u32, LiveRange) = .init(self.allocator);

        var instruction_idx: u32 = 0;
        var next_val: u32 = 0;
        for (func.blocks.items, 0..) |block, block_idx| {
            for (block.parameters, 0..) |_, p_idx| {
                const vidx = func.param_indices.items[block_idx][p_idx];

                try live_ranges.put(vidx, LiveRange{
                    .start = instruction_idx,
                    .end = 0,
                    .value = vidx,
                    .expired = false,
                });

                next_val += 1;
                instruction_idx += 1;
            }

            for (block.instructions.items) |inst| {
                switch (inst) {
                    .iconst, .iadd, .isub, .imul, .icmp => {
                        try live_ranges.put(next_val, LiveRange{
                            .start = instruction_idx,
                            .end = 0,
                            .value = next_val,
                            .expired = true,
                        });

                        next_val += 1;
                    },

                    .brif, .jmp, .ret => {},
                }

                instruction_idx += 1;
            }
        }

        instruction_idx = 0;
        next_val = 0;

        // compute the end time now, it will always be instruction_idx
        // ensure to add these checks for instructions which use values
        for (func.blocks.items) |block| {
            instruction_idx += @as(u32, @intCast(block.parameters.len));

            for (block.instructions.items) |inst| {
                switch (inst) {
                    .iconst => {},

                    .iadd => |add| {
                        live_ranges.getPtr(add.lhs).?.end = instruction_idx;
                        live_ranges.getPtr(add.rhs).?.end = instruction_idx;
                    },

                    .isub => |sub| {
                        live_ranges.getPtr(sub.lhs).?.end = instruction_idx;
                        live_ranges.getPtr(sub.rhs).?.end = instruction_idx;
                    },

                    .imul => |mul| {
                        live_ranges.getPtr(mul.lhs).?.end = instruction_idx;
                        live_ranges.getPtr(mul.rhs).?.end = instruction_idx;
                    },

                    .icmp => |cmp| {
                        live_ranges.getPtr(cmp.lhs).?.end = instruction_idx;
                        live_ranges.getPtr(cmp.rhs).?.end = instruction_idx;
                    },

                    .brif => |brif| {
                        live_ranges.getPtr(brif.condition).?.end = instruction_idx;
                    },

                    .ret => |ret| {
                        live_ranges.getPtr(ret.value).?.end = instruction_idx;
                    },

                    .jmp => |jmp| {
                        for (jmp.args) |arg| {
                            live_ranges.getPtr(arg).?.end = instruction_idx;
                        }
                    },
                }

                instruction_idx += 1;
            }
        }

        return live_ranges;
    }

    fn scanLiveRanges(
        self: *CodeGen,
        live_ranges: std.AutoHashMap(u32, LiveRange),
    ) !std.AutoHashMap(u32, Register) {
        var ranges: std.ArrayList(LiveRange) = .empty;
        var iter = live_ranges.iterator();

        while (iter.next()) |e| {
            try ranges.append(self.allocator, e.value_ptr.*);
        }

        std.mem.sort(LiveRange, ranges.items, {}, struct {
            fn lessThanFn(_: void, a: LiveRange, b: LiveRange) bool {
                return a.start < b.start;
            }
        }.lessThanFn);

        var result: std.AutoHashMap(u32, Register) = .init(self.allocator);
        var free_regs: std.ArrayList(Register) = .empty;
        var active_ranges: std.ArrayList(LiveRange) = .empty;

        const regs = [_]Register{ .rax, .rbx, .r10, .r11, .r12, .r13, .r14, .r15 };
        for (regs) |r| try free_regs.append(self.allocator, r);

        for (ranges.items) |range| {
            // expire
            for (active_ranges.items) |*a| {
                if (a.end < range.start) {
                    a.expired = true;
                    try free_regs.append(self.allocator, result.get(a.value).?);
                }
            }

            // remove
            var i: usize = 0;
            while (i < active_ranges.items.len) {
                if (active_ranges.items[i].expired) {
                    _ = active_ranges.swapRemove(i);
                } else {
                    i += 1;
                }
            }

            // assign
            if (free_regs.items.len > 0) {
                const r = free_regs.pop();
                try result.put(range.value, r.?);
                try active_ranges.append(self.allocator, range);
            }
        }

        return result;
    }

    pub fn compile(self: *CodeGen, func: *IR.Function) !void {
        const arg_registers = if (comptime builtin.os.tag == .windows)
            [_]Register{ .rcx, .rdx, .r8, .r9 }
        else
            [_]Register{ .rdi, .rsi, .rdx, .rcx };

        const live_ranges = try self.computeLiveRanges(func);
        var regalloc = try RegAlloc.init(
            self.allocator,
            self.emitter,
            live_ranges,
            &arg_registers,
        );

        var labels: std.ArrayList(usize) = .empty;
        defer labels.deinit(self.allocator);

        for (func.blocks.items) |_| {
            try labels.append(self.allocator, try self.emitter.label());
        }

        var inst_idx: usize = 0;
        var next_val: u32 = 0;
        for (func.blocks.items, 0..) |block, block_idx| {
            next_val += @as(u32, @intCast(block.parameters.len));
            inst_idx += block.parameters.len;

            for (block.parameters, 0..) |_, param_idx| {
                const val_idx = func.param_indices.items[block_idx][param_idx];
                _ = try regalloc.alloc(val_idx, arg_registers[param_idx]);
            }

            try self.emitter.bind(labels.items[block_idx]);

            const give_frames_plz = live_ranges.count() > 8;
            // ok
            if (give_frames_plz) try self.emitter.enter(64);

            for (block.instructions.items) |inst| {
                switch (inst) {
                    .iconst => |constant| {
                        const reg = try regalloc.alloc(next_val, null);

                        try self.emitter.mov_reg_imm64(reg, constant);
                        next_val += 1;
                    },

                    .iadd => |add| {
                        const reg = try regalloc.alloc(next_val, null);
                        const lhs = regalloc.get(add.lhs) orelse try regalloc.reload(add.lhs);
                        const rhs = regalloc.get(add.rhs) orelse try regalloc.reload(add.rhs);

                        try self.emitter.mov_reg_reg(reg, lhs);
                        try self.emitter.add_reg_reg(reg, rhs);
                        next_val += 1;
                    },

                    .isub => |sub| {
                        const reg = try regalloc.alloc(next_val, null);
                        const lhs = regalloc.get(sub.lhs) orelse try regalloc.reload(sub.lhs);
                        const rhs = regalloc.get(sub.rhs) orelse try regalloc.reload(sub.rhs);

                        try self.emitter.mov_reg_reg(reg, lhs);
                        try self.emitter.sub_reg_reg(reg, rhs);
                        next_val += 1;
                    },

                    .imul => |mul| {
                        const reg = try regalloc.alloc(next_val, null);
                        const lhs = regalloc.get(mul.lhs) orelse try regalloc.reload(mul.lhs);
                        const rhs = regalloc.get(mul.rhs) orelse try regalloc.reload(mul.rhs);

                        try self.emitter.mov_reg_reg(reg, lhs);
                        try self.emitter.imul_reg_reg(reg, rhs);
                        next_val += 1;
                    },

                    .icmp => |icmp| {
                        const reg = try regalloc.alloc(next_val, null);
                        const lhs = regalloc.get(icmp.lhs) orelse try regalloc.reload(icmp.lhs);
                        const rhs = regalloc.get(icmp.rhs) orelse try regalloc.reload(icmp.rhs);

                        try self.emitter.cmp_reg_reg(lhs, rhs);
                        try self.emitter.setcc(icmp.kind, .rax);
                        try self.emitter.movzx_reg_reg8(.rax, .rax);
                        try self.emitter.mov_reg_reg(reg, .rax);
                        next_val += 1;
                    },

                    .brif => |brif| {
                        // don't want to corrupt registers if the condition isn't true or false
                        // so jump to the correct label depending on condition to avoid this
                        const true_guard = try self.emitter.label();
                        const false_guard = try self.emitter.label();

                        const condition = regalloc.get(brif.condition) orelse try regalloc.reload(brif.condition);

                        try self.emitter.cmp_reg_imm32(condition, 0);
                        try self.emitter.jnz(true_guard);

                        try self.emitter.bind(false_guard);
                        if (brif.false_args.len > 0) {
                            for (brif.false_args, 0..) |arg, arg_idx| {
                                // a really simple move of the jmp arg regs to block arg regs.
                                const target_reg = arg_registers[arg_idx];
                                const src_reg = regalloc.get(arg) orelse try regalloc.reload(arg);
                                try self.emitter.mov_reg_reg(target_reg, src_reg);
                            }
                        }
                        try self.emitter.jmp(labels.items[brif.false_block]);

                        try self.emitter.bind(true_guard);
                        if (brif.true_args.len > 0) {
                            for (brif.true_args, 0..) |arg, arg_idx| {
                                // a really simple move of the jmp arg regs to block arg regs.
                                const target_reg = arg_registers[arg_idx];
                                const src_reg = regalloc.get(arg) orelse try regalloc.reload(arg);
                                try self.emitter.mov_reg_reg(target_reg, src_reg);
                            }
                        }
                        try self.emitter.jmp(labels.items[brif.true_block]);
                    },

                    .jmp => |jmp| {
                        for (jmp.args, 0..) |arg, arg_idx| {
                            // a really simple move of the jmp arg regs to block arg regs.
                            const target_reg = arg_registers[arg_idx];
                            const src_reg = regalloc.get(arg) orelse try regalloc.reload(arg);
                            try self.emitter.mov_reg_reg(target_reg, src_reg);
                        }

                        try self.emitter.jmp(labels.items[jmp.to_block]);
                    },

                    .ret => |r| {
                        const val = regalloc.get(r.value) orelse try regalloc.reload(r.value);
                        try self.emitter.mov_reg_reg(.rax, val);
                        if (give_frames_plz) try self.emitter.leave();
                        try self.emitter.ret();
                    },
                }

                inst_idx += 1;

                var iter = live_ranges.iterator();
                while (iter.next()) |e| {
                    if (e.value_ptr.end == inst_idx - 1) {
                        try regalloc.free(e.value_ptr.value);
                    }
                }
            }
        }
    }
};
