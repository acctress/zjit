const std = @import("std");

pub const Emitter = @import("core/emitter.zig").Emitter;
pub const Register = @import("core/regs.zig").Register;
pub const Encode = @import("core/encode.zig").encode;
pub const IR = @import("core/ir.zig").IR;

test "mov immediate and ret" {
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

test "push n pop" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    try emitter.mov_reg_imm64(.rbx, 78);
    try emitter.push(.rbx);
    try emitter.pop(.rax);
    try emitter.ret();

    const f = try emitter.commit(*const fn () callconv(.c) i64);
    const result = f();

    try std.testing.expectEqual(78, result);
}

fn number_gen() callconv(.c) i64 {
    return 420;
}

test "call and return" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    try emitter.call(&number_gen);
    try emitter.ret();

    const f = try emitter.commit(*const fn () callconv(.c) i64);
    const result = f();

    try std.testing.expectEqual(420, result);
}

fn print_num_and_return() callconv(.c) i64 {
    const num = 420;
    std.debug.print("{d}\n", .{num});
    return num;
}

test "call a dynamic function and return" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    try emitter.call(&print_num_and_return);
    try emitter.ret();

    const f = try emitter.commit(*const fn () callconv(.c) i64);
    const result = f();

    try std.testing.expectEqual(420, result);
}

test "zero rax register with xor" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    try emitter.mov_reg_imm64(.rax, 42);
    try emitter.xor_reg_reg(.rax, .rax);
    try emitter.ret();

    const f = try emitter.commit(*const fn () callconv(.c) i64);
    const result = f();

    try std.testing.expectEqual(0, result);
}

test "and of 0b1100 AND 0b1010" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    try emitter.mov_reg_imm64(.rax, 0b1100);
    try emitter.mov_reg_imm64(.rcx, 0b1010);
    try emitter.and_reg_reg(.rax, .rcx);
    try emitter.ret();

    const f = try emitter.commit(*const fn () callconv(.c) i64);
    const result = f();

    try std.testing.expectEqual(0b1000, result);
}

test "or of 0b1100 AND 0b1010" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    try emitter.mov_reg_imm64(.rax, 0b1100);
    try emitter.mov_reg_imm64(.rcx, 0b1010);
    try emitter.or_reg_reg(.rax, .rcx);
    try emitter.ret();

    const f = try emitter.commit(*const fn () callconv(.c) i64);
    const result = f();

    try std.testing.expectEqual(0b1110, result);
}

test "not of 0" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    try emitter.mov_reg_imm64(.rax, 0);
    try emitter.not_reg(.rax);
    try emitter.ret();

    const f = try emitter.commit(*const fn () callconv(.c) i64);
    const result = f();

    try std.testing.expectEqual(-1, result);
}

test "shift one left two times" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    try emitter.mov_reg_imm64(.rcx, 2);
    try emitter.mov_reg_imm64(.rax, 1);
    try emitter.shl_reg(.rax);
    try emitter.ret();

    const f = try emitter.commit(*const fn () callconv(.c) i64);
    const result = f();

    try std.testing.expectEqual(4, result);
}

test "shift eight right two times" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    try emitter.mov_reg_imm64(.rcx, 2);
    try emitter.mov_reg_imm64(.rax, 8);
    try emitter.shr_reg(.rax);
    try emitter.ret();

    const f = try emitter.commit(*const fn () callconv(.c) i64);
    const result = f();

    try std.testing.expectEqual(2, result);
}

test "move reg from mem" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    try emitter.enter(16);
    try emitter.mov_reg_imm64(.rax, 42);
    try emitter.mov_mem_reg(.rbp, -8, .rax);
    try emitter.mov_reg_mem(.rax, .rbp, -8);
    try emitter.leave();
    try emitter.ret();

    const f = try emitter.commit(*const fn () callconv(.c) i64);
    const result = f();

    try std.testing.expectEqual(42, result);
}

test "move mem from reg" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    try emitter.enter(16);
    try emitter.mov_reg_imm64(.rcx, 1337);
    try emitter.mov_mem_reg(.rbp, -8, .rcx); // store into mem
    try emitter.mov_reg_mem(.rax, .rbp, -8); // read from mem
    try emitter.leave();
    try emitter.ret();

    const f = try emitter.commit(*const fn () callconv(.c) i64);
    const result = f();

    try std.testing.expectEqual(1337, result);
}

test "twenty divided by four, expect five" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    try emitter.mov_reg_imm64(.rax, 20);
    try emitter.mov_reg_imm64(.rcx, 4);
    try emitter.cqo();
    try emitter.idiv(.rcx);
    try emitter.ret();

    const f = try emitter.commit(*const fn () callconv(.c) i64);
    const result = f();

    try std.testing.expectEqual(5, result);
}

test "quick neg" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    try emitter.mov_reg_imm64(.rax, 42);
    try emitter.neg(.rax);
    try emitter.ret();

    const f = try emitter.commit(*const fn () callconv(.c) i64);
    const result = f();

    try std.testing.expectEqual(-42, result);
}

test "move 32-bit immediate to memory" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    try emitter.enter(16);
    try emitter.mov_mem_imm32(.rbp, -8, 999);
    try emitter.mov_reg_mem(.rax, .rbp, -8);
    try emitter.leave();
    try emitter.ret();

    const f = try emitter.commit(*const fn () callconv(.c) i64);
    const result = f();

    try std.testing.expectEqual(999, result);
}

test "test memory with rsp as the base" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    try emitter.sub_reg_imm32(.rsp, 8);
    try emitter.mov_mem_imm32(.rsp, 0, 42);
    try emitter.mov_reg_mem(.rax, .rsp, 0);
    try emitter.add_reg_imm32(.rsp, 8);
    try emitter.ret();

    const f = try emitter.commit(*const fn () callconv(.c) i64);
    const result = f();

    try std.testing.expectEqual(42, result);
}

fn print_count(count: i64) callconv(.c) void {
    std.debug.print("{d}\n", .{count});
}

test "count down from 10 to 0 and print the current number" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    const loop_start = try emitter.label();

    try emitter.mov_reg_imm64(.rcx, 10);
    try emitter.bind(loop_start);
    try emitter.push(.rcx);
    try emitter.call(&print_count);
    try emitter.pop(.rcx);
    try emitter.dec_reg(.rcx);
    try emitter.jnz(loop_start);
    try emitter.ret();

    const f = try emitter.commit(*const fn () callconv(.c) i64);
    const result = f();

    // expect nothing cuz we dont care
    try std.testing.expectEqual(0, result);
}

// message needs to be sentinel so std.debug.print knows where to end
fn print_message(message: [*:0]const u8) callconv(.c) void {
    std.debug.print("{s}\n", .{message});
}

test "load a string pointer into memory and return it" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    const str: []const u8 = "hellooo\x00";

    try emitter.sub_reg_imm32(.rsp, 40); // setup stack frame
    try emitter.mov_reg_imm64(.rcx, @as(i64, @intCast(@intFromPtr(str.ptr))));
    try emitter.call(&print_message);
    try emitter.add_reg_imm32(.rsp, 40);
    try emitter.xor_reg_reg(.rax, .rax);
    try emitter.ret();

    const f = try emitter.commit(*const fn () callconv(.c) i64);
    const result = f();

    // expect nothing cuz we dont care
    try std.testing.expectEqual(0, result);
}

test "simple ir function" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var function: IR.Function = try .init(allocator);

    try function.createBlock();
    const v0 = try function.iconst(42);
    const v1 = try function.iconst(85);
    const v2 = try function.iadd(v0, v1);
    try function.ret(v2);

    try std.testing.expectEqual(0, 0);
}
