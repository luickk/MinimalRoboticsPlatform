const std = @import("std");
const sysCalls = @import("userSysCallInterface");
const kprint = sysCalls.SysCallPrint.kprint;

var test_counter: usize = 0;

export fn app_main(pid: usize) linksection(".text.main") callconv(.C) noreturn {
    while (true) {
        test_counter += 1;
        kprint("app{d} test print {d} \n", .{ pid, test_counter });
        sysCalls.wait(100000);
        // kprint("app1 test print \n", .{});

        if (test_counter == 40000) {
            test_counter += 1;
            sysCalls.killProcessRecursively(1);
        }
    }
}
