const std = @import("std");

const sysCalls = @import("userSysCallInterface");
const kprint = sysCalls.SysCallPrint.kprint;

var test_counter: usize = 0;

export fn app_main(pid: usize) linksection(".text.main") callconv(.C) noreturn {
    // kprint("{x} my pid \n", .{0xdead});
    _ = pid;
    while (true) {
        test_counter += 1;
        kprint("app2 test print {d} \n", .{test_counter});
        // kprint("app2 test print \n", .{});

        // if (test_counter > 10000) {
        //     kprint("KILLING PROCESS \n", .{});
        //     sysCalls.killProcess(pid);
        // }
    }
}

fn getCurrentSp() usize {
    var x: usize = asm ("mov %[curr], sp"
        : [curr] "=r" (-> usize),
    );
    return x;
}
