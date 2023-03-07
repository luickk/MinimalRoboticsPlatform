const std = @import("std");
const appLib = @import("appLib");
const AppAlloc = appLib.AppAllocator;
const sysCalls = appLib.sysCalls;
const kprint = appLib.sysCalls.SysCallPrint.kprint;

var test_counter: usize = 0;

export fn app_main(pid: usize) linksection(".text.main") callconv(.C) noreturn {
    kprint("app1 initial pid: {d} \n", .{pid});
    while (true) {
        test_counter += 1;

        kprint("app{d} test print {d} \n", .{ pid, test_counter });
        // if (test_counter == 40000) {
        //     test_counter += 1;
        //     // sysCalls.killProcess(1);
        //     sysCalls.killProcessRecursively(1);
        // }
    }
}
