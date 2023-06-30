const std = @import("std");
const appLib = @import("appLib");
const AppAlloc = appLib.AppAllocator;
const sysCalls = appLib.sysCalls;
const kprint = appLib.sysCalls.SysCallPrint.kprint;

var test_counter: usize = 0;

export fn app_main(pid: usize) linksection(".text.main") callconv(.C) noreturn {
    _ = pid;
    while (true) {
        test_counter += 1;
        // sysCalls.sleep(1000000000) catch |err| {
        //     kprint("[app panic] sleep error: {s} \n", .{@errorName(err)});
        // };
        kprint("sleep test app \n", .{});
    }
}
