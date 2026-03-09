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

pub const XmmRegister = enum(u4) {
    xmm0,
    xmm1,
    xmm2,
    xmm3,
    xmm4,
    xmm5,
    xmm6,
    xmm7,
    xmm8,
    xmm9,
    xmm10,
    xmm11,
    xmm12,
    xmm13,
    xmm14,
    xmm15,

    pub fn enc(reg: XmmRegister) u3 {
        return @as(u3, @truncate(@intFromEnum(reg)));
    }

    pub fn ext(reg: XmmRegister) bool {
        return (@intFromEnum(reg) >= @intFromEnum(XmmRegister.xmm8) and
            @intFromEnum(reg) <= @intFromEnum(XmmRegister.xmm15));
    }
};
