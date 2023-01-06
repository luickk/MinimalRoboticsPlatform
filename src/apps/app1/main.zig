const std = @import("std");

const kprint = @import("userSysCallInterface").SysCallPrint.kprint;

export fn app_main() linksection(".text.main") callconv(.Naked) noreturn {
    while (true) {
        // kprint("app1 test print > {d} < \n", .{getCurrentEl()});
        kprint("app1 test print \n", .{});
    }
}

fn getCurrentEl() usize {
    var x: usize = asm ("mrs %[curr], CurrentEL"
        : [curr] "=r" (-> usize),
    );
    return x >> 2;
}
