const std = @import("std");
const appLib = @import("appLib");
const AppAlloc = appLib.AppAllocator;
const sysCalls = appLib.sysCalls;
const kprint = appLib.sysCalls.SysCallPrint.kprint;

export fn app_main(pid: usize) linksection(".text.main") callconv(.C) noreturn {
    kprint("app1 initial pid: {d} \n", .{pid});

    sysCalls.openTopic(1) catch |e| {
        kprint("syscall openTopic err: {s} \n", .{@errorName(e)});
        while (true) {}
    };
    var counter: u8 = 0;
    while (true) {
        // kprint("app{d} test push \n", .{pid});
        kprint("trying \n", .{});
        sysCalls.pushToTopic(1, &[_]u8{counter}) catch |e| {
            kprint("syscall pushToTopic err: {s} \n", .{@errorName(e)});
            while (true) {}
        };
        kprint("pushin: {d} \n", .{counter});
        counter += 1;

        // const topics_interfaces_read = @intToPtr(*volatile [1000]usize, 0x20000000).*;
        // kprint("topics interface read: {any} \n", .{topics_interfaces_read});
    }
}
