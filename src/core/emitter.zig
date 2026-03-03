const std = @import("std");
const ExecBuffer = @import("buffer.zig").ExecBuffer;
const regs = @import("regs.zig");
const encode = @import("encode.zig").encode;

const Register = regs.Register;

pub const Emitter = struct {
    buffer: ExecBuffer,

    pub fn init(size: usize) !Emitter {
        return .{
            .buffer = try .init(size),
        };
    }

    pub fn deinit(self: *Emitter) void {
        self.buffer.deinit();
    }

    pub fn commit(self: *Emitter, comptime F: type) !F {
        return self.buffer.commit(F);
    }

    pub fn mov_reg_imm64(self: *Emitter, reg: Register, imm: i64) !void {
        // std.debug.print("+ mov_reg_imm64(reg = {s}, imm = {})\n", .{ @tagName(reg), imm });

        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, .rax, reg),
            0xB8 + @as(u8, reg.enc()),
        });

        try self.buffer.writeImm(i64, imm);
    }

    pub fn mov_reg_reg(self: *Emitter, dest: Register, src: Register) !void {
        // std.debug.print("+ mov_reg_reg(src = {s}, dest = {s})\n", .{ @tagName(src), @tagName(dest) });

        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, src, dest),
            0x89,
            encode.modrm(src, dest),
        });
    }

    pub fn add_reg_reg(self: *Emitter, dest: Register, src: Register) !void {
        // std.debug.print("+ add_reg_reg(src = {s}, dest = {s})\n", .{ @tagName(src), @tagName(dest) });

        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, src, dest),
            0x01,
            encode.modrm(src, dest),
        });
    }

    pub fn sub_reg_reg(self: *Emitter, dest: Register, src: Register) !void {
        // std.debug.print("+ sub_reg_reg(src = {s}, dest = {s})\n", .{ @tagName(src), @tagName(dest) });

        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, src, dest),
            0x29,
            encode.modrm(src, dest),
        });
    }

    pub fn imul_reg_reg(self: *Emitter, dest: Register, src: Register) !void {
        // std.debug.print("+ imul_reg_reg(src = {s}, dest = {s})\n", .{ @tagName(src), @tagName(dest) });

        try self.buffer.writeBytes(&[_]u8{
            encode.rex(true, dest, src),
            0x0F,
            0xAF,
            encode.modrm(dest, src),
        });
    }

    pub fn ret(self: *Emitter) !void {
        std.debug.print("+ ret\n", .{});
        try self.buffer.writeByte(0xC3);
    }
};
