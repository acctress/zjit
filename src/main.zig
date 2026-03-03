const std = @import("std");
const zjit = @import("zjit");
const builtin = @import("builtin");

pub fn main() !void {
    var emitter: zjit.Emitter = try .init(1024);
    defer emitter.deinit();

    if (comptime builtin.os.tag == .windows) {
        try emitter.mov_reg_reg(.rax, .rcx);
        try emitter.add_reg_reg(.rax, .rdx);
    } else {
        try emitter.mov_reg_reg(.rax, .rdi);
        try emitter.add_reg_reg(.rax, .rsi);
    }

    try emitter.ret();

    const f = try emitter.commit(*const fn (i64, i64) callconv(.c) i64);
    const result = f(10, 10);

    std.debug.print("Result = {}\n", .{result});
}
