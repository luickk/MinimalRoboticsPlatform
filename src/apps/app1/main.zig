const std = @import("std");

const kprint = @import("userSysCallInterface").SysCallPrint.kprint;

var test_counter: usize = 0;

export fn app_main() linksection(".text.main") callconv(.Naked) noreturn {
    while (true) {
        test_counter += 1;
        kprint("app1 test print {d} \n", .{test_counter});
    }
}
