pub const Emitter = @import("core/emitter.zig").Emitter;
pub const Register = @import("core/regs.zig").Register;
pub const Encode = @import("core/encode.zig").encode;

test "mov immediate and ret" {
    const std = @import("std");

    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    try emitter.mov_reg_imm64(.rax, 47);
    try emitter.ret();

    const f = try emitter.commit(*const fn () callconv(.c) i64);
    const result = f();

    try std.testing.expectEqual(47, result);
}

test "sub two values in registers" {
    const std = @import("std");

    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    try emitter.mov_reg_imm64(.rax, 100);
    try emitter.mov_reg_imm64(.rcx, 50);
    try emitter.sub_reg_reg(.rax, .rcx);
    try emitter.ret();

    const f = try emitter.commit(*const fn () callconv(.c) i64);
    const result = f();

    try std.testing.expectEqual(50, result);
}

test "add two numbers from caller" {
    const std = @import("std");
    const builtin = @import("builtin");

    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
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

    try std.testing.expectEqual(20, result);
}

test "jump over an instruction so it never runs" {
    const std = @import("std");

    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    const jump_here = try emitter.label();

    try emitter.jmp(jump_here);
    try emitter.mov_reg_imm64(.rax, 1);
    try emitter.bind(jump_here); // <<-- jump over here!!!
    try emitter.mov_reg_imm64(.rax, 2);
    try emitter.ret();

    const f = try emitter.commit(*const fn () callconv(.c) i64);
    const result = f();

    try std.testing.expectEqual(2, result);
}

test "countdown from one hundred to zero and return the num of iterations" {
    const std = @import("std");

    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    const loop_start = try emitter.label();

    try emitter.mov_reg_imm64(.rax, 0);
    try emitter.mov_reg_imm64(.rcx, 100);
    try emitter.bind(loop_start);
    try emitter.add_reg_imm32(.rax, 1);
    try emitter.dec_reg(.rcx);
    try emitter.jnz(loop_start);
    try emitter.ret();

    const f = try emitter.commit(*const fn () callconv(.c) i64);
    const result = f();

    try std.testing.expectEqual(100, result);
}
