const std = @import("std");

const sysCalls = @import("userSysCallInterface");
const kprint = sysCalls.SysCallPrint.kprint;

var test_counter: usize = 0;

export fn app_main(pid: usize) linksection(".text.main") callconv(.C) noreturn {
    kprint("initial pid: {d} \n", .{pid});
    while (true) {
        test_counter += 1;
        kprint("app{d} test print {d} \n", .{ sysCalls.getPid(), test_counter });
        if (test_counter == 10000) {
            test_counter += 1;
            sysCalls.forkProcess(pid);
            // sysCalls.killProcess(pid);
        }
    }
}
