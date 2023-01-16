const std = @import("std");

const kprint = @import("userSysCallInterface").SysCallPrint.kprint;

var test_counter: usize = 0;

export fn app_main() linksection(".text.main") callconv(.C) noreturn {
    // const pid: usize = 100;
    // kprint("my pid: {d} \n", .{pid});
    while (true) {
        test_counter += 1;
        kprint("app1 test print {d} \n", .{test_counter});
        // kprint("app1 test print \n", .{});
    }
}
