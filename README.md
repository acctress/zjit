# zjit
A x86-64 JIT assembler in Zig for Linux and Windows, call machine code as a native function.

# Features
Supported instructions: `mov, add, sub, imul, idiv, ret, jmp, jz, jnz, jl, jge, cmp, dec, push, pop, call`

Calling a user defined Zig function is this simple:
```zig
fn my_func() callconv(.c) i64 {
    return 69;
}
...
try emitter.call(&my_func);
try emitter.ret();
...
```

# Calling Conventions
Windows: `rcx, rdx, r8, r9`

Linux: `rdi, rsi, rdx, rcx`

# Example
```zig
const std = @import("std");
const zjit = @import("zjit");
const builtin = @import("builtin");

pub fn main() !void {
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

    std.debug.print("Result = {}\n", .{result});
}
```

Check out tests/examples in `src/root.zig` to see how zjit works!
And don't forget to run `zig build test` to ensure zjit hasn't broken.

# Resources & Links Used
* [VirtualAlloc](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-virtualalloc)
* [VirtualFree](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-virtualfree)
* [std.posix.mmap](https://ziglang.org/documentation/master/std/#std.posix.mmap)
* [Intel x86-64 Manual](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html)
* [System V AMD64 ABI](https://gitlab.com/x86-psABIs/x86-64-ABI)
* [Microsoft x64 calling convention](https://learn.microsoft.com/en-us/cpp/build/x64-calling-convention)
* [x86-64 Opcodes](https://www.felixcloutier.com/x86/)