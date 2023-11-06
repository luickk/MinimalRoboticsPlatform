const std = @import("std");
const appLib = @import("appLib");
const board = @import("board");
const arm = @import("arm");
const cpuContext = arm.cpuContext;
const AppAlloc = appLib.AppAllocator;
const sysCalls = appLib.sysCalls;
const kprint = appLib.sysCalls.SysCallPrint.kprint;

var test_counter: usize = 0;

export fn app_main(pid: usize) linksection(".text.main") callconv(.C) noreturn {
    kprint("app1 initial pid: {d} \n", .{pid});
    while (true) {
        test_counter += 1;

        kprint("app{d} test print {d} \n", .{ pid, test_counter });
        kprint("sleeping... \n", .{});
        sysCalls.sleep(std.time.ns_per_s) catch |e| {
            kprint("syscall err {s} \n", .{@errorName(e)});
        };
        // if (test_counter == 40000) {
        //     test_counter += 1;
        //     // sysCalls.killTask(1);
        //     sysCalls.killTaskRecursively(1);
        // }
    }
}
