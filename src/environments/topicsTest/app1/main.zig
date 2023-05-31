const std = @import("std");
const appLib = @import("appLib");
const AppAlloc = appLib.AppAllocator;
const sysCalls = appLib.sysCalls;
const kprint = appLib.sysCalls.SysCallPrint.kprint;

export fn app_main(pid: usize) linksection(".text.main") callconv(.C) noreturn {
    kprint("app1 initial pid: {d} \n", .{pid});

    sysCalls.openTopic(1);
    var counter: u8 = 0;
    while (true) {
        // kprint("app{d} test push \n", .{pid});
        if (counter < 100) {
            sysCalls.pushToTopic(1, &[_]u8{counter});
            kprint("pushin: {d} \n", .{counter});
            counter += 1;
        }
    }
}
