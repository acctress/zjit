pub const Register = enum(u4) {
    rax,
    rcx,
    rdx,
    rbx,
    rsp,
    rbp,
    rsi,
    rdi,
    r8,
    r9,
    r10,
    r11,
    r12,
    r13,
    r14,
    r15,

    /// Returns the 3 bit encoding of the register
    pub fn enc(reg: Register) u3 {
        return @as(u3, @truncate(@intFromEnum(reg)));
    }

    /// Is this an extended register?
    pub fn ext(reg: Register) bool {
        return (@intFromEnum(reg) >= @intFromEnum(Register.r8) and
            @intFromEnum(reg) <= @intFromEnum(Register.r15));
    }
};
