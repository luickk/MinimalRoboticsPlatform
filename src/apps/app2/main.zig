const std = @import("std");

const kprint = @import("userSysCallInterface").SysCallPrint.kprint;

const arm = @import("arm");
const ProccessorRegMap = arm.processor.ProccessorRegMap;

var test_counter: usize = 0;

export fn app_main() linksection(".text.main") callconv(.Naked) noreturn {
    while (true) {
        test_counter += 1;
        // kprint("app2 test print > {d} < \n", .{getCurrentEl()});
        kprint("app2 test print {d} \n", .{test_counter});
    }
}
