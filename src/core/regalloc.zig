const std = @import("std");
const Emitter = @import("emitter.zig").Emitter;
const AutoHashMap = std.AutoHashMap;
const ArrayList = std.ArrayList;
const IR = @import("ir.zig").IR;
const LiveRange = @import("codegen.zig").LiveRange;
const Register = @import("regs.zig").Register;
const Value = IR.Value;

pub const RegAlloc = struct {
    allocator: std.mem.Allocator,
    assignments: AutoHashMap(Value, Register),
    spilled: AutoHashMap(Value, i32), // (value, stack offset)
    did_spill: bool,
    free_regs: ArrayList(Register),
    live_ranges: AutoHashMap(Value, LiveRange),
    stack_offset: i32,
    emitter: *Emitter,

    pub fn init(
        allocator: std.mem.Allocator,
        emitter: *Emitter,
        live_ranges: AutoHashMap(u32, LiveRange),
        _: []const Register,
    ) !RegAlloc {
        var free_regs: ArrayList(Register) = .empty;

        const general_purpose = [_]Register{
            .rax,
            .rbx,
            .r10,
            .r11,
            .r12,
            .r13,
            .r14,
            .r15,
        };

        for (general_purpose) |reg| {
            try free_regs.append(allocator, reg);
        }

        return .{
            .allocator = allocator,
            .emitter = emitter,
            .live_ranges = live_ranges,
            .free_regs = free_regs,
            .assignments = .init(allocator),
            .spilled = .init(allocator),
            .did_spill = false,
            .stack_offset = -8,
        };
    }

    pub fn alloc(self: *RegAlloc, value: Value, hint: ?Register) !Register {
        if (hint) |reg| {
            for (self.free_regs.items, 0..) |free_reg, idx| {
                if (free_reg == reg) {
                    _ = self.free_regs.swapRemove(idx);
                    break;
                }
            }

            try self.assignments.put(value, reg);
            return reg;
        }

        if (self.free_regs.items.len > 0) {
            if (self.free_regs.pop()) |reg| {
                try self.assignments.put(value, reg);
                return reg;
            }
        }

        self.did_spill = true;

        var longest_lifetime: usize = 0;
        var live_range: LiveRange = undefined;
        var iter = self.assignments.iterator();
        while (iter.next()) |e| {
            const lv = self.live_ranges.get(e.key_ptr.*) orelse continue;
            if (lv.end > longest_lifetime) {
                longest_lifetime = lv.end;
                live_range = lv;
            }
        }

        if (longest_lifetime == 0) return error.NoSpillCandidate;

        const assignment_reg = self.assignments.get(live_range.value).?;

        try self.emitter.mov_mem_reg(.rbp, self.stack_offset, assignment_reg);
        try self.spilled.put(live_range.value, self.stack_offset);
        self.stack_offset -= 8; // x86-64!!! had this on -= 4 :sob:

        _ = self.assignments.remove(live_range.value);
        try self.assignments.put(value, assignment_reg);

        return assignment_reg;
    }

    pub fn reload(self: *RegAlloc, value: Value) !Register {
        if (self.spilled.contains(value)) {
            const stk_offset = self.spilled.get(value).?;
            if (self.free_regs.pop()) |free_reg| {
                try self.emitter.mov_reg_mem(free_reg, .rbp, stk_offset);
                try self.assignments.put(value, free_reg);
                _ = self.spilled.remove(value);
                return free_reg;
            } else {
                return error.NoFreeRegisters;
            }
        }

        return error.ValueNotSpilled;
    }

    pub fn free(self: *RegAlloc, value: Value) !void {
        if (self.get(value)) |reg| {
            _ = self.assignments.remove(value);
            try self.free_regs.append(self.allocator, reg);
        }

        if (self.spilled.contains(value)) {
            _ = self.spilled.remove(value);
        }
    }

    pub fn get(self: *RegAlloc, value: Value) ?Register {
        return self.assignments.get(value);
    }
};
