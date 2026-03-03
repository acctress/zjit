const std = @import("std");
const builtin = @import("builtin");

pub const ExecBuffer = struct {
    mem: []u8,
    writePos: usize,
    committed: bool,

    pub fn init(size: usize) !ExecBuffer {
        var buf: ExecBuffer = .{
            .mem = undefined,
            .writePos = 0,
            .committed = false,
        };

        if (comptime builtin.os.tag == .windows) {
            const mem = try std.os.windows.VirtualAlloc(
                null,
                size,
                std.os.windows.MEM_COMMIT | std.os.windows.MEM_RESERVE,
                std.os.windows.PAGE_EXECUTE_READWRITE,
            );

            buf.mem = @as([*]u8, @ptrCast(mem))[0..size];
        } else {
            buf.mem = try std.posix.mmap(
                null,
                size,
                std.posix.PROT.READ | std.posix.PROT.WRITE,
                .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
                -1,
                0,
            );
        }

        return buf;
    }

    pub fn deinit(self: *ExecBuffer) void {
        if (comptime builtin.os.tag == .windows) {
            std.os.windows.VirtualFree(self.mem.ptr, 0, std.os.windows.MEM_RELEASE);
        } else {
            std.posix.munmap(self.mem);
        }
    }

    pub fn writeByte(self: *ExecBuffer, byte: u8) !void {
        if (self.committed) @panic("Tried writing data whilst memory had already been comitted.");
        if (self.writePos >= self.mem.len) @panic("Write position of data exceeds maximum size.");

        self.mem[self.writePos] = byte;
        self.writePos += 1;
    }

    pub fn writeBytes(self: *ExecBuffer, bytes: []const u8) !void {
        if (self.committed) @panic("Tried writing data whilst memory had already been comitted.");
        if (self.writePos + bytes.len >= self.mem.len) @panic("Write position of data exceeds maximum size.");

        for (bytes) |byte| {
            self.mem[self.writePos] = byte;
            self.writePos += 1;
        }
    }

    pub fn writeImm(self: *ExecBuffer, comptime T: type, value: T) !void {
        if (self.committed) @panic("Tried writing data whilst memory had already been comitted.");
        if (self.writePos + @sizeOf(T) >= self.mem.len) @panic("Write position of data exceeds maximum size.");

        std.mem.writeInt(
            T,
            self.mem[self.writePos..][0..@sizeOf(T)],
            value,
            .little,
        );

        self.writePos += @sizeOf(T);
    }

    pub fn commit(self: *ExecBuffer, comptime F: type) !F {
        if (comptime builtin.os.tag == .windows) {
            self.committed = true;
        } else {
            try std.posix.mprotect(
                self.mem,
                std.posix.PROT.READ | std.posix.PROT.EXEC,
            );

            self.committed = true;
        }

        return @as(F, @ptrCast(self.mem.ptr));
    }
};
