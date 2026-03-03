const std = @import("std");

const regs = @import("regs.zig");
const Register = regs.Register;

pub const encode = struct {
    /// w signifies if a 64-bit or 32-bit integer is being processed.
    pub fn rex(w: bool, reg1: Register, reg2: Register) u8 {
        var byte: u8 = 0x40;
        byte |= @as(u8, @intFromBool(w)) << 3;
        byte |= @as(u8, @intFromBool(reg1.ext())) << 2;
        byte |= @as(u8, @intFromBool(reg2.ext())) << 0;
        return byte;
    }

    pub fn modrm(reg: Register, rm: Register) u8 {
        std.debug.print("   * modrm(reg = {s}, rm = {s})\n", .{ @tagName(reg), @tagName(rm) });

        var byte: u8 = 0xC0;
        byte |= @as(u8, reg.enc()) << 3;
        byte |= @as(u8, rm.enc());
        return byte;
    }
};
