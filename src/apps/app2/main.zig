const std = @import("std");

const sysCalls = @import("userSysCallInterface");
const kprint = sysCalls.SysCallPrint.kprint;

var test_counter: usize = 0;

export fn app_main(pid: usize) linksection(".text.main") callconv(.C) noreturn {
    kprint("my pid: {d} \n", .{pid});
    while (true) {
        test_counter += 1;
        kprint("app2 test print {d} \n", .{test_counter});
        // kprint("app2 test print \n", .{});

        if (test_counter > 10000) {
            sysCalls.killProcess(pid);
        }
    }
}
