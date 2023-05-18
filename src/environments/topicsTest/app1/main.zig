const std = @import("std");
const appLib = @import("appLib");
const AppAlloc = appLib.AppAllocator;
const sysCalls = appLib.sysCalls;
const kprint = appLib.sysCalls.SysCallPrint.kprint;

export fn app_main(pid: usize) linksection(".text.main") callconv(.C) noreturn {
    kprint("app1 initial pid: {d} \n", .{pid});

    sysCalls.openTopic(1);
    var test_data = [_]u8{ 10, 10, 10 };
    while (true) {
        kprint("app{d} test print/push \n", .{pid});
        sysCalls.pushToTopic(1, &test_data);
    }
}
