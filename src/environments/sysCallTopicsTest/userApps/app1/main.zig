const std = @import("std");
const appLib = @import("appLib");
const AppAlloc = appLib.AppAllocator;
const sysCalls = appLib.sysCalls;
const kprint = appLib.sysCalls.SysCallPrint.kprint;

export fn app_main(pid: usize) linksection(".text.main") callconv(.C) noreturn {
    kprint("app1 initial pid: {d} \n", .{pid});

    var counter: usize = 0;

    var payload: []u8 = undefined;
    payload.ptr = @ptrCast([*]u8, &counter);
    payload.len = @sizeOf(@TypeOf(counter));
    while (true) {
        var data_written = sysCalls.pushToTopic("front-ultrasonic-proximity", payload) catch |e| {
            kprint("syscall pushToTopic err: {s} \n", .{@errorName(e)});
            while (true) {}
        };
        if (data_written < payload.len) kprint("partially written {d}/ {d} bytes \n", .{ data_written, payload.len });
        kprint("pushin: {d} \n", .{counter});
        counter += 1;

        // const topics_interfaces_read = @intToPtr(*volatile [1000]usize, 0x20000000).*;
        // kprint("topics interface read: {any} \n", .{topics_interfaces_read});
    }
}
