const std = @import("std");
const ExecBuffer = @import("buffer.zig").ExecBuffer;
const regs = @import("regs.zig");
const encode = @import("encode.zig").encode;
const builtin = @import("builtin");

const Register = regs.Register;

pub const Label = struct {
    target: ?usize,
    fixups: std.ArrayList(usize),
};

/// Identical to IR's CompKind, but explicitly for setcc instructions
pub const SetCCKind = enum { eq, ne, lt, le, gt, ge };

pub const Emitter = struct {
    allocator: std.mem.Allocator,
    buffer: ExecBuffer,
    labels: std.ArrayList(Label),

    pub fn init(allocator: std.mem.Allocator, size: usize) !Emitter {
        return .{
            .allocator = allocator,
            .buffer = try .init(size),
            .labels = .empty,
        };
    }

    pub fn deinit(self: *Emitter) void {
        self.buffer.deinit();

        for (self.labels.items) |*i| {
            i.fixups.deinit(self.allocator);
        }

        self.labels.deinit(self.allocator);
    }

    pub fn commit(self: *Emitter, comptime F: type) !F {
        return self.buffer.commit(F);
    }

    pub fn label(self: *Emitter) !usize {
        const l: Label = .{
            .target = null,
            .fixups = .empty,
        };

        try self.labels.append(self.allocator, l);
        return self.labels.items.len - 1;
    }

    pub fn bind(self: *Emitter, label_idx: usize) !void {
        self.labels.items[label_idx].target = self.buffer.writePos;

        for (self.labels.items[label_idx].fixups.items) |f| {
            const offset: i32 = @intCast(
                @as(i64, @intCast(self.labels.items[label_idx].target.?)) - (@as(i64, @intCast(f)) + 4),
            );

            std.mem.writeInt(
                i32,
                self.buffer.mem[f..][0..4],
                offset,
                .little,
            );
        }
    }

    pub fn nop(self: *Emitter, count: u32) !void {
        for (0..count) |_| try self.buffer.writeByte(0x90);
    }

    pub fn patchAt(self: *Emitter, pos: usize, bytes: []const u8) !void {
        for (bytes, 0..) |byte, i| {
            self.buffer.mem[pos + i] = byte;
        }
    }

    pub fn mov_reg_imm64(self: *Emitter, reg: Register, imm: i64) !void {
        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, .rax, reg),
            0xB8 + @as(u8, reg.enc()),
        });

        try self.buffer.writeImm(i64, imm);
    }

    pub fn mov_reg_reg(self: *Emitter, dest: Register, src: Register) !void {
        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, src, dest),
            0x89,
            encode.modrm(src, dest),
        });
    }

    pub fn mov_reg_mem(self: *Emitter, dest: Register, base: Register, offset: i32) !void {
        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, dest, base),
            0x8B,
            0x80 | @as(u8, dest.enc()) << 3 | @as(u8, base.enc()),
        });

        if (base == .rsp) {
            // emit a sib byte if we're using rsp as the base register
            try self.buffer.writeByte(0x24);
        }

        try self.buffer.writeImm(i32, offset);
    }

    pub fn mov_mem_reg(self: *Emitter, base: Register, offset: i32, src: Register) !void {
        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, src, base),
            0x89,
            0x80 | @as(u8, src.enc()) << 3 | @as(u8, base.enc()),
        });

        if (base == .rsp) {
            // emit a sib byte if we're using rsp as the base register
            try self.buffer.writeByte(0x24);
        }

        try self.buffer.writeImm(i32, offset);
    }

    /// Move imm32 sign extended to 64-bits to r/m64.
    pub fn mov_mem_imm32(self: *Emitter, base: Register, offset: i32, imm: i32) !void {
        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, .rax, base),
            0xC7,
            0x80 | @as(u8, base.enc()),
        });

        if (base == .rsp) {
            // emit a sib byte if we're using rsp as the base register
            try self.buffer.writeByte(0x24);
        }

        try self.buffer.writeImm(i32, offset);
        try self.buffer.writeImm(i32, imm);
    }

    pub fn movzx_reg_reg8(self: *Emitter, dest: Register, src: Register) !void {
        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, dest, src),
            0x0F,
            0xB6,
            encode.modrm(dest, src),
        });
    }

    pub fn add_reg_reg(self: *Emitter, dest: Register, src: Register) !void {
        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, src, dest),
            0x01,
            encode.modrm(src, dest),
        });
    }

    pub fn add_reg_imm32(self: *Emitter, dest: Register, imm: i32) !void {
        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, .rax, dest), 0x81, 0xC0 | (0 << 3) | @as(u8, dest.enc()),
        });

        try self.buffer.writeImm(i32, imm);
    }

    pub fn sub_reg_reg(self: *Emitter, dest: Register, src: Register) !void {
        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, src, dest),
            0x29,
            encode.modrm(src, dest),
        });
    }

    pub fn sub_reg_imm32(self: *Emitter, dest: Register, imm: i32) !void {
        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, .rax, dest), 0x81, 0xC0 | (5 << 3) | @as(u8, dest.enc()),
        });

        try self.buffer.writeImm(i32, imm);
    }

    pub fn imul_reg_reg(self: *Emitter, dest: Register, src: Register) !void {
        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, dest, src),
            0x0F,
            0xAF,
            encode.modrm(dest, src),
        });
    }

    pub fn ret(self: *Emitter) !void {
        try self.buffer.writeByte(0xC3);
    }

    pub fn jmp(self: *Emitter, label_idx: usize) !void {
        try self.buffer.writeByte(0xE9);
        const fix_pos = self.buffer.writePos;

        if (self.labels.items[label_idx].target != null) {
            const offset: i32 = @intCast(
                @as(i64, @intCast(self.labels.items[label_idx].target.?)) - (@as(i64, @intCast(fix_pos)) + 4),
            );

            std.mem.writeInt(
                i32,
                self.buffer.mem[fix_pos..][0..4],
                offset,
                .little,
            );

            self.buffer.writePos += 4;
        } else {
            try self.buffer.writeImm(i32, 0);
            try self.labels.items[label_idx].fixups.append(self.allocator, fix_pos);
        }
    }

    pub fn jz(self: *Emitter, label_idx: usize) !void {
        try self.buffer.writeBytes(&[_]u8{ 0x0F, 0x84 });
        const fix_pos = self.buffer.writePos;

        if (self.labels.items[label_idx].target != null) {
            const offset: i32 = @intCast(
                @as(i64, @intCast(self.labels.items[label_idx].target.?)) - (@as(i64, @intCast(fix_pos)) + 4),
            );

            std.mem.writeInt(
                i32,
                self.buffer.mem[fix_pos..][0..4],
                offset,
                .little,
            );

            self.buffer.writePos += 4;
        } else {
            try self.buffer.writeImm(i32, 0);
            try self.labels.items[label_idx].fixups.append(self.allocator, fix_pos);
        }
    }

    pub fn jnz(self: *Emitter, label_idx: usize) !void {
        try self.buffer.writeBytes(&[_]u8{ 0x0F, 0x85 });
        const fix_pos = self.buffer.writePos;

        if (self.labels.items[label_idx].target != null) {
            const offset: i32 = @intCast(
                @as(i64, @intCast(self.labels.items[label_idx].target.?)) - (@as(i64, @intCast(fix_pos)) + 4),
            );

            std.mem.writeInt(
                i32,
                self.buffer.mem[fix_pos..][0..4],
                offset,
                .little,
            );

            self.buffer.writePos += 4;
        } else {
            try self.buffer.writeImm(i32, 0);
            try self.labels.items[label_idx].fixups.append(self.allocator, fix_pos);
        }
    }

    pub fn jl(self: *Emitter, label_idx: usize) !void {
        try self.buffer.writeBytes(&[_]u8{ 0x0F, 0x8C });
        const fix_pos = self.buffer.writePos;

        if (self.labels.items[label_idx].target != null) {
            const offset: i32 = @intCast(
                @as(i64, @intCast(self.labels.items[label_idx].target.?)) - (@as(i64, @intCast(fix_pos)) + 4),
            );

            std.mem.writeInt(
                i32,
                self.buffer.mem[fix_pos..][0..4],
                offset,
                .little,
            );

            self.buffer.writePos += 4;
        } else {
            try self.buffer.writeImm(i32, 0);
            try self.labels.items[label_idx].fixups.append(self.allocator, fix_pos);
        }
    }

    pub fn jge(self: *Emitter, label_idx: usize) !void {
        try self.buffer.writeBytes(&[_]u8{ 0x0F, 0x8D });
        const fix_pos = self.buffer.writePos;

        if (self.labels.items[label_idx].target != null) {
            const offset: i32 = @intCast(
                @as(i64, @intCast(self.labels.items[label_idx].target.?)) - (@as(i64, @intCast(fix_pos)) + 4),
            );

            std.mem.writeInt(
                i32,
                self.buffer.mem[fix_pos..][0..4],
                offset,
                .little,
            );

            self.buffer.writePos += 4;
        } else {
            try self.buffer.writeImm(i32, 0);
            try self.labels.items[label_idx].fixups.append(self.allocator, fix_pos);
        }
    }

    pub fn cmp_reg_reg(self: *Emitter, dest: Register, src: Register) !void {
        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, src, dest),
            0x3B,
            encode.modrm(dest, src),
        });
    }

    pub fn cmp_reg_imm32(self: *Emitter, reg: Register, imm: i32) !void {
        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, .rax, reg), 0x81, 0xC0 | (7 << 3) | @as(u8, reg.enc()),
        });

        try self.buffer.writeImm(i32, imm);
    }

    pub fn dec_reg(self: *Emitter, reg: Register) !void {
        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, .rax, reg),
            0xFF,
            0xC0 | (1 << 3) | @as(u8, reg.enc()),
        });
    }

    pub fn push(self: *Emitter, reg: Register) !void {
        if (reg.ext()) try self.buffer.writeByte(encode.rex(false, .rax, reg));
        try self.buffer.writeBytes(&[_]u8{
            0xFF,
            0xC0 | (6 << 3) | @as(u8, reg.enc()),
        });
    }

    pub fn pop(self: *Emitter, reg: Register) !void {
        if (reg.ext()) try self.buffer.writeByte(encode.rex(false, .rax, reg));
        try self.buffer.writeBytes(&[_]u8{
            0x8F,
            0xC0 | (0 << 3) | @as(u8, reg.enc()),
        });
    }

    pub fn call(self: *Emitter, fptr: anytype) !void {
        try self.sub_reg_imm32(.rsp, 8);
        try self.mov_reg_imm64(.rax, @as(i64, @intCast(@intFromPtr(fptr))));
        try self.buffer.writeBytes(&[_]u8{ 0xFF, 0xD0 }); // modrm hardcoded in as it always uses rax
        try self.add_reg_imm32(.rsp, 8);
    }

    pub fn enter(self: *Emitter, size: usize) !void {
        // alignment
        const alignmed = (size + 15) & ~@as(usize, 15);
        try self.push(.rbp);
        try self.mov_reg_reg(.rbp, .rsp);
        try self.sub_reg_imm32(
            .rsp,
            if (comptime builtin.os.tag == .windows) @as(i32, @intCast(alignmed)) + 32 else @as(i32, @intCast(alignmed)),
        );
    }

    pub fn leave(self: *Emitter) !void {
        try self.mov_reg_reg(.rsp, .rbp);
        try self.pop(.rbp);
    }

    pub fn and_reg_reg(self: *Emitter, dest: Register, src: Register) !void {
        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, src, dest),
            0x21,
            encode.modrm(src, dest),
        });
    }

    pub fn or_reg_reg(self: *Emitter, dest: Register, src: Register) !void {
        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, src, dest),
            0x09,
            encode.modrm(src, dest),
        });
    }

    pub fn xor_reg_reg(self: *Emitter, dest: Register, src: Register) !void {
        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, src, dest),
            0x31,
            encode.modrm(src, dest),
        });
    }

    pub fn not_reg(self: *Emitter, reg: Register) !void {
        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, .rax, reg),
            0xF7,
            0xC0 | (2 << 3) | @as(u8, reg.enc()),
        });
    }

    pub fn shl_reg(self: *Emitter, reg: Register) !void {
        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, .rax, reg),
            0xD3,
            0xC0 | (4 << 3) | @as(u8, reg.enc()),
        });
    }

    pub fn shr_reg(self: *Emitter, reg: Register) !void {
        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, .rax, reg),
            0xD3,
            0xC0 | (5 << 3) | @as(u8, reg.enc()),
        });
    }

    pub fn cqo(self: *Emitter) !void {
        try self.buffer.writeBytes(&[_]u8{
            encode.REX_NO_OPS,
            0x99,
        });
    }

    pub fn idiv(self: *Emitter, reg: Register) !void {
        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, .rax, reg),
            0xF7,
            0xC0 | (7 << 3) | @as(u8, reg.enc()),
        });
    }

    /// Two's complement negate r/m64.
    pub fn neg(self: *Emitter, reg: Register) !void {
        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, .rax, reg),
            0xF7,
            0xC0 | (3 << 3) | @as(u8, reg.enc()),
        });
    }

    /// These instructions for all SetCCKind use `al` which is the low byte of rax, no REX.
    /// TODO: implement support for registers r8-r15, add REX.B.
    pub fn setcc(self: *Emitter, kind: SetCCKind, reg: Register) !void {
        switch (kind) {
            .eq => try self.buffer.writeBytes(&[_]u8{ 0x0F, 0x94, 0xC0 | @as(u8, reg.enc()) }),
            .ne => try self.buffer.writeBytes(&[_]u8{ 0x0F, 0x95, 0xC0 | @as(u8, reg.enc()) }),
            .lt => try self.buffer.writeBytes(&[_]u8{ 0x0F, 0x9C, 0xC0 | @as(u8, reg.enc()) }),
            .le => try self.buffer.writeBytes(&[_]u8{ 0x0F, 0x9E, 0xC0 | @as(u8, reg.enc()) }),
            .gt => try self.buffer.writeBytes(&[_]u8{ 0x0F, 0x9F, 0xC0 | @as(u8, reg.enc()) }),
            .ge => try self.buffer.writeBytes(&[_]u8{ 0x0F, 0x9D, 0xC0 | @as(u8, reg.enc()) }),
        }
    }
};
