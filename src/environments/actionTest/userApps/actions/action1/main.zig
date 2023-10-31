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
    _ = pid;
    while (true) {}
}
