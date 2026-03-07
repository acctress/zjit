const std = @import("std");
const IR = @import("ir.zig").IR;
const Register = @import("regs.zig").Register;
const Emitter = @import("emitter.zig").Emitter;
const builtin = @import("builtin");
const RegAlloc = @import("regalloc.zig").RegAlloc;
const encode = @import("encode.zig").encode;

const GEN_REG_COUNT: usize = 8;
const PTR_SIZE: usize = 8;

const CALLEE_SAVED = if (builtin.os.tag == .windows)
    [_]Register{ .rbx, .rsi, .rdi, .r12, .r13, .r14, .r15 }
else
    [_]Register{ .rbx, .r12, .r13, .r14, .r15 };

const ARG_REGISTERS = if (builtin.os.tag == .windows)
    [_]Register{ .rcx, .rdx, .r8, .r9 }
else
    [_]Register{ .rdi, .rsi, .rdx, .rcx };

pub const GenModule = struct {
    allocator: std.mem.Allocator,
    functions: std.AutoHashMap(usize, *const anyopaque),

    pub fn init(allocator: std.mem.Allocator) GenModule {
        return .{
            .allocator = allocator,
            .functions = .init(allocator),
        };
    }

    pub fn deinit(self: *GenModule) void {
        self.functions.deinit();
    }

    pub fn getFunction(self: *GenModule, idx: usize, comptime Fn: type) ?Fn {
        if (self.functions.contains(idx))
            return @ptrCast(self.functions.get(idx).?);
        return null;
    }
};

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

fn isCalleeRegister(reg: Register) bool {
    for (CALLEE_SAVED) |r| {
        if (reg == r) return true;
    }

    return false;
}

pub const CodeGen = struct {
    allocator: std.mem.Allocator,
    emitter: *Emitter,

    pub fn init(allocator: std.mem.Allocator, emitter: *Emitter) CodeGen {
        return .{
            .allocator = allocator,
            .emitter = emitter,
        };
    }

    /// Compute the maximum amount of concurrent live values
    fn computeMaximumLive(self: *CodeGen, live_range: std.AutoHashMap(u32, LiveRange)) !usize {
        var boundaries: std.ArrayList(usize) = .empty;
        var iter = live_range.iterator();
        while (iter.next()) |r| {
            try boundaries.append(self.allocator, r.value_ptr.start);
            try boundaries.append(self.allocator, r.value_ptr.end);
        }

        var peak: usize = 0;
        for (boundaries.items) |i| {
            var count: usize = 0;
            iter = live_range.iterator();
            while (iter.next()) |r| {
                if (r.value_ptr.start <= i and i <= r.value_ptr.end) {
                    count += 1;
                }
            }

            peak = @max(peak, count);
        }

        return peak;
    }

    /// Compute the lifetimes of registers being used by have a range of usage, when it reaches it's end it's register is usable, cleaned up.
    fn computeLiveRanges(self: *CodeGen, func: *const IR.Function) !std.AutoHashMap(u32, LiveRange) {
        var live_ranges: std.AutoHashMap(u32, LiveRange) = .init(self.allocator);
        var instruction_idx: u32 = 0;

        for (func.args.items) |arg_v| {
            try live_ranges.put(arg_v, LiveRange{
                .start = instruction_idx,
                .end = 0,
                .value = arg_v,
                .expired = false,
            });

            instruction_idx += 1;
        }

        for (func.blocks.items, 0..) |block, block_idx| {
            for (block.parameters, 0..) |_, p_idx| {
                const vidx = func.param_indices.items[block_idx][p_idx];

                try live_ranges.put(vidx, LiveRange{
                    .start = instruction_idx,
                    .end = 0,
                    .value = vidx,
                    .expired = false,
                });

                instruction_idx += 1;
            }

            for (block.instructions.items) |inst| {
                switch (inst) {
                    .iconst => |i| try live_ranges.put(i.result, LiveRange{ .start = instruction_idx, .end = 0, .value = i.result, .expired = true }),
                    .iadd => |i| try live_ranges.put(i.result, LiveRange{ .start = instruction_idx, .end = 0, .value = i.result, .expired = true }),
                    .isub => |i| try live_ranges.put(i.result, LiveRange{ .start = instruction_idx, .end = 0, .value = i.result, .expired = true }),
                    .imul => |i| try live_ranges.put(i.result, LiveRange{ .start = instruction_idx, .end = 0, .value = i.result, .expired = true }),
                    .icmp => |i| try live_ranges.put(i.result, LiveRange{ .start = instruction_idx, .end = 0, .value = i.result, .expired = true }),
                    .brif, .jmp, .ret => {},
                }

                instruction_idx += 1;
            }
        }

        instruction_idx = 0;

        for (func.args.items) |_| {
            instruction_idx += 1;
        }

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

    pub fn compileModule(self: *CodeGen, module: IR.Module) !GenModule {
        var mod: GenModule = .init(self.allocator);

        for (module.functions.items, 0..) |*func, func_idx| {
            try self.compileFunction(func, &mod, func_idx);
        }

        _ = try self.emitter.buffer.commit(*const anyopaque);
        return mod;
    }

    fn inRegister(self: *CodeGen, regalloc: *RegAlloc, value: IR.Value) !Register {
        if (regalloc.get(value)) |r| {
            return r;
        }

        if (regalloc.spilled.get(value)) |offset| {
            const temp: Register = .r10;
            try self.emitter.mov_reg_mem(temp, .rbp, offset);
            return temp;
        }

        return error.ValueNotFound;
    }

    fn compileFunction(self: *CodeGen, func: *IR.Function, mod: *GenModule, func_idx: usize) !void {
        // first pass, essentially pre allocate registers, calculate life times, and check if we need frames
        const live_ranges = try self.computeLiveRanges(func);
        const peak_live = try self.computeMaximumLive(live_ranges);

        var regalloc: RegAlloc = try .init(
            self.allocator,
            live_ranges,
            &ARG_REGISTERS,
        );

        try regalloc.walk(func, &ARG_REGISTERS);

        const slots = if (peak_live > GEN_REG_COUNT) peak_live - GEN_REG_COUNT else 0;
        const stk_size = slots * PTR_SIZE;
        const frames_needed = stk_size > 0;

        var used_callee_regs_buf: [32]Register = undefined;
        var ucr_count: usize = 0;

        var iter = regalloc.used_registers.keyIterator();
        while (iter.next()) |reg| {
            if (isCalleeRegister(reg.*)) {
                used_callee_regs_buf[ucr_count] = reg.*;
                ucr_count += 1;
            }
        }

        const used_callee_regs = used_callee_regs_buf[0..ucr_count];
        const prologue = self.emitter.buffer.writePos;

        try self.emitter.nop(@as(u32, @intCast(used_callee_regs.len)) * 3);

        if (frames_needed) try self.emitter.enter(stk_size);

        var labels: std.ArrayList(usize) = .empty;
        defer labels.deinit(self.allocator);

        for (func.blocks.items) |_| {
            try labels.append(self.allocator, try self.emitter.label());
        }

        var inst_idx: usize = 0;
        for (func.blocks.items, 0..) |*block, block_idx| {
            inst_idx += block.parameters.len;

            try self.emitter.bind(labels.items[block_idx]);

            for (block.instructions.items) |*inst| {
                switch (inst.*) {
                    .iconst => |i| {
                        const reg = regalloc.get(i.result) orelse try regalloc.reload(i.result);
                        try self.emitter.mov_reg_imm64(reg, i.constant);
                    },

                    .iadd => |i| {
                        const lhs = try self.inRegister(&regalloc, i.lhs);
                        const rhs = try self.inRegister(&regalloc, i.rhs);
                        const reg = regalloc.get(i.result) orelse return error.ResultNotAllocated;
                        try self.emitter.mov_reg_reg(reg, lhs);
                        try self.emitter.add_reg_reg(reg, rhs);
                    },

                    .isub => |i| {
                        const reg = regalloc.get(i.result) orelse try regalloc.reload(i.result);
                        const lhs = regalloc.get(i.lhs) orelse try regalloc.reload(i.lhs);
                        const rhs = regalloc.get(i.rhs) orelse try regalloc.reload(i.rhs);
                        try self.emitter.mov_reg_reg(reg, lhs);
                        try self.emitter.sub_reg_reg(reg, rhs);
                    },

                    .imul => |i| {
                        const reg = regalloc.get(i.result) orelse try regalloc.reload(i.result);
                        const lhs = regalloc.get(i.lhs) orelse try regalloc.reload(i.lhs);
                        const rhs = regalloc.get(i.rhs) orelse try regalloc.reload(i.rhs);
                        try self.emitter.mov_reg_reg(reg, lhs);
                        try self.emitter.imul_reg_reg(reg, rhs);
                    },

                    .icmp => |i| {
                        const reg = regalloc.get(i.result) orelse try regalloc.reload(i.result);
                        const lhs = regalloc.get(i.lhs) orelse try regalloc.reload(i.lhs);
                        const rhs = regalloc.get(i.rhs) orelse try regalloc.reload(i.rhs);
                        try self.emitter.cmp_reg_reg(lhs, rhs);
                        try self.emitter.setcc(i.kind, .rax);
                        try self.emitter.movzx_reg_reg8(.rax, .rax);
                        try self.emitter.mov_reg_reg(reg, .rax);
                    },

                    .brif => |i| {
                        const true_guard = try self.emitter.label();
                        const false_guard = try self.emitter.label();
                        const condition = regalloc.get(i.condition) orelse try regalloc.reload(i.condition);

                        try self.emitter.cmp_reg_imm32(condition, 0);
                        try self.emitter.jnz(true_guard);

                        try self.emitter.bind(false_guard);
                        for (i.false_args, 0..) |arg, arg_idx| {
                            const target_reg = ARG_REGISTERS[arg_idx];
                            const src_reg = regalloc.get(arg) orelse try regalloc.reload(arg);
                            try self.emitter.mov_reg_reg(target_reg, src_reg);
                        }
                        try self.emitter.jmp(labels.items[i.false_block]);

                        try self.emitter.bind(true_guard);
                        for (i.true_args, 0..) |arg, arg_idx| {
                            const target_reg = ARG_REGISTERS[arg_idx];
                            const src_reg = regalloc.get(arg) orelse try regalloc.reload(arg);
                            try self.emitter.mov_reg_reg(target_reg, src_reg);
                        }
                        try self.emitter.jmp(labels.items[i.true_block]);
                    },

                    .jmp => |i| {
                        for (i.args, 0..) |arg, arg_idx| {
                            const target_reg = ARG_REGISTERS[arg_idx];
                            const src_reg = regalloc.get(arg) orelse try regalloc.reload(arg);
                            try self.emitter.mov_reg_reg(target_reg, src_reg);
                        }
                        try self.emitter.jmp(labels.items[i.to_block]);
                    },

                    .ret => |i| {
                        const value = regalloc.get(i.value) orelse try regalloc.reload(i.value);

                        try self.emitter.mov_reg_reg(.rax, value);
                        if (ucr_count > 0) {
                            var pop_count = ucr_count;
                            while (pop_count > 0) : (pop_count -= 1) {
                                try self.emitter.pop(used_callee_regs[pop_count - 1]);
                            }
                        }

                        if (frames_needed) {
                            try self.emitter.leave();
                        }
                        try self.emitter.ret();
                    },
                }

                inst_idx += 1;

                var live_iter = live_ranges.iterator();
                while (live_iter.next()) |*e| {
                    if (e.*.value_ptr.end == inst_idx - 1) {
                        try regalloc.free(e.*.value_ptr.value);
                    }
                }
            }
        }

        var patch_pos = prologue;
        for (used_callee_regs) |reg| {
            const bytes = if (reg.ext())
                &[_]u8{ encode.rex(false, .rax, reg), 0xFF, 0xC0 | (6 << 3) | @as(u8, reg.enc()) }
            else
                &[_]u8{ 0xFF, 0xC0 | (6 << 3) | @as(u8, reg.enc()) };

            try self.emitter.patchAt(patch_pos, bytes);
            patch_pos += bytes.len;
        }

        const entry_ptr: *const anyopaque = @ptrCast(&self.emitter.buffer.mem[prologue]);
        try mod.functions.put(func_idx, entry_ptr);
    }
};
