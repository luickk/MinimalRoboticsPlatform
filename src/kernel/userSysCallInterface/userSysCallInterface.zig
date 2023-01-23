const std = @import("std");
const utils = @import("utils");

pub const SysCallPrint = struct {
    const Self = @This();
    pub const Writer = std.io.Writer(*Self, error{}, appendWrite);

    pub fn writer(self: *Self) Writer {
        return .{ .context = self };
    }

    fn callKernelPrint(data: [*]const u8, len: usize) void {
        asm volatile (
        // args
            \\mov x0, %[data_addr]
            \\mov x1, %[len]
            // sys call id
            \\mov x8, #0
            \\svc #0
            :
            : [data_addr] "r" (@ptrToInt(data)),
              [len] "r" (len),
            : "x0", "x1", "x8"
        );
        // asm volatile ("brk 0xdead");
    }
    /// Same as `append` except it returns the number of bytes written, which is always the same
    /// as `m.len`. The purpose of this function existing is to match `std.io.Writer` API.
    fn appendWrite(self: *Self, data: []const u8) error{}!usize {
        _ = self;
        // asm volatile ("brk 0xdead");
        callKernelPrint(data.ptr, data.len);
        return data.len;
    }

    pub fn kprint(comptime print_string: []const u8, args: anytype) void {
        var tempW: SysCallPrint = undefined;
        std.fmt.format(tempW.writer(), print_string, args) catch |err| {
            @panic(err);
        };
    }
};

pub fn killProcess(pid: usize) noreturn {
    asm volatile (
    // args
        \\mov x0, %[pid]
        // sys call id
        \\mov x8, #1
        \\svc #0
        :
        : [pid] "r" (pid),
        : "x0", "x8"
    );
    while (true) {}
}

pub fn forkProcess(pid: usize) void {
    asm volatile (
    // args
        \\mov x0, %[pid]
        // sys call id
        \\mov x8, #2
        \\svc #0
        :
        : [pid] "r" (pid),
        : "x0", "x8"
    );
}

pub fn getPid() usize {
    return asm (
        \\mov x8, #3
        \\svc #0
        \\mov %[curr], x0
        : [curr] "=r" (-> usize),
        :
        : "x0", "x8"
    );
}

pub fn killProcessRecursively(starting_pid: usize) void {
    asm volatile (
    // args
        \\mov x0, %[pid]
        // sys call id
        \\mov x8, #4
        \\svc #0
        :
        : [pid] "r" (starting_pid),
        : "x0", "x8"
    );
}

// todo => fix that scheduler gets stuck at higher delays
pub fn wait(delay_in_nano_secs: usize) void {
    asm volatile (
    // args
        \\mov x0, %[delay]
        // sys call id
        \\mov x8, #5
        \\svc #0
        :
        : [delay] "r" (delay_in_nano_secs),
        : "x0", "x8"
    );
}
