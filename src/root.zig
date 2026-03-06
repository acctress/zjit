const std = @import("std");

pub const Emitter = @import("core/emitter.zig").Emitter;
pub const Register = @import("core/regs.zig").Register;
pub const Encode = @import("core/encode.zig").encode;
pub const IR = @import("core/ir.zig").IR;
pub const CodeGen = @import("core/codegen.zig").CodeGen;

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

test "ir function with params" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var function: IR.Function = try .init(allocator);

    const block = try function.createBlock(&[_]IR.Type{ .i64, .i64 });
    const v0 = block.param(0);
    const v1 = block.param(1);
    const v2 = try function.iadd(v0, v1);
    try function.ret(v2);

    try std.testing.expectEqual(0, 0);
}

test "compile ir adder function" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    var adder: IR.Function = try .init(allocator);

    _ = try adder.createBlock(IR.no_types);
    const v0 = try adder.iconst(42);
    const v1 = try adder.iconst(85);
    const v2 = try adder.iadd(v0, v1);
    try adder.ret(v2);

    var code_gen: CodeGen = .init(allocator, &emitter);
    try code_gen.compile(&adder);

    const f = try emitter.commit(*const fn () callconv(.c) i64);
    const result = f();

    try std.testing.expectEqual(127, result);
}

test "call ir function with params and pass args" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    var function: IR.Function = try .init(allocator);

    const block = try function.createBlock(&[_]IR.Type{ .i64, .i64 });
    const v0 = block.param(0);
    const v1 = block.param(1);
    const v2 = try function.iadd(v0, v1);
    try function.ret(v2);

    var code_gen: CodeGen = .init(allocator, &emitter);
    try code_gen.compile(&function);

    const f = try emitter.commit(*const fn (i64, i64) callconv(.c) i64);
    const result = f(10, 10);

    try std.testing.expectEqual(result, 20);
}

test "function return 1 if arg is not zero else return 0" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    var function: IR.Function = try .init(allocator);

    {
        const entry = try function.createBlock(&[_]IR.Type{.i64});
        const v0 = entry.param(0);
        try function.brif(v0, 1, 2, IR.no_args, IR.no_args);

        // true
        _ = try function.createBlock(IR.no_types);
        const v_true = try function.iconst(1);
        try function.ret(v_true);

        // false
        _ = try function.createBlock(IR.no_types);
        const v_false = try function.iconst(0);
        try function.ret(v_false);
    }

    var code_gen: CodeGen = .init(allocator, &emitter);
    try code_gen.compile(&function);

    const f = try emitter.commit(*const fn (i64) callconv(.c) i64);

    try std.testing.expectEqual(1, f(1));
    try std.testing.expectEqual(0, f(0));
}

test "function which is a max function" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    var function: IR.Function = try .init(allocator);

    {
        const entry = try function.createBlock(&[_]IR.Type{ .i64, .i64 });
        const v0 = entry.param(0);
        const v1 = entry.param(1);
        const v2 = try function.icmp(.gt, v0, v1);
        try function.brif(v2, 1, 2, IR.no_args, IR.no_args);

        // true
        _ = try function.createBlock(IR.no_types);
        try function.ret(v0);

        // false
        _ = try function.createBlock(IR.no_types);
        try function.ret(v1);
    }

    var code_gen: CodeGen = .init(allocator, &emitter);
    try code_gen.compile(&function);

    const f = try emitter.commit(*const fn (i64, i64) callconv(.c) i64);

    std.debug.print("{d}\n", .{f(5, 10)});

    try std.testing.expectEqual(10, f(10, 5));
    try std.testing.expectEqual(15, f(15, 10));
    try std.testing.expectEqual(4, f(4, 2));
    try std.testing.expectEqual(1, f(1, 0));
    try std.testing.expectEqual(5, f(5, 4));
}

test "test cmp" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emitter: Emitter = try .init(allocator, 1024);
    defer emitter.deinit();

    var function: IR.Function = try .init(allocator);

    {
        const entry = try function.createBlock(&[_]IR.Type{ .i64, .i64 });
        const v0 = entry.param(0);
        const v1 = entry.param(1);
        const v2 = try function.icmp(.gt, v0, v1);
        try function.ret(v2);
    }

    var code_gen: CodeGen = .init(allocator, &emitter);
    try code_gen.compile(&function);

    const f = try emitter.commit(*const fn (i64, i64) callconv(.c) i64);

    try std.testing.expectEqual(0, f(5, 10));
    try std.testing.expectEqual(0, f(2, 10));
    try std.testing.expectEqual(0, f(7, 10));
    try std.testing.expectEqual(0, f(8, 10));
    try std.testing.expectEqual(1, f(11, 10));
    try std.testing.expectEqual(1, f(56, 10));
    try std.testing.expectEqual(1, f(120, 10));
}

// test "sum 1 to n IR loop test" {
//     var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
//     defer arena.deinit();
//     const allocator = arena.allocator();

//     var emitter: Emitter = try .init(allocator, 1024);
//     defer emitter.deinit();

//     var function: IR.Function = try .init(allocator);

//     {
//         const entry = try function.createBlock(&[_]IR.Type{ .i64, .i64 });
//         const n = entry.param(0);
//         try function.jmp(0, &[_]IR.Value{
//             try function.iconst(0),
//             try function.iconst(0),
//         });

//         const b1 = try function.createBlock(&[_]IR.Type{ .i64, .i64 });
//         const i = b1.param(0);
//         const acc = b1.param(1);
//         const v = try function.icmp(.lt, i, n);
//         try function.brif(v, 1, 2, &[_]IR.Value{ i, acc }, &[_]IR.Value{acc});

//         const b2 = try function.createBlock(&[_]IR.Type{ .i64, .i64 });
//         const i2_ = b2.param(0);
//         const acc2 = b2.param(1);
//         const to_add = try function.iconst(1);
//         _ = try function.iadd(i2_, to_add);
//         try function.jmp(0, &[_]IR.Value{acc2});

//         const b3 = try function.createBlock(&[_]IR.Type{.i64});
//         const acc3 = b3.param(0);
//         try function.ret(acc3);
//     }

//     var code_gen: CodeGen = .init(allocator, &emitter);
//     try code_gen.compile(&function);

//     const f = try emitter.commit(*const fn (i64) callconv(.c) i64);

//     try std.testing.expectEqual(10, f(5));
// }
