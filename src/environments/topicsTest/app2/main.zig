const std = @import("std");

const board = @import("board");
const appLib = @import("appLib");
const Mutex = appLib.Mutex;
const AppAlloc = appLib.AppAllocator;
const sysCalls = appLib.sysCalls;
const utils = appLib.utils;
const kprint = appLib.sysCalls.SysCallPrint.kprint;

var test_counter: usize = 0;

var shared_thread_counter: isize = 0;
var mutex = Mutex.init();
var shared_mutex: *Mutex = &mutex;

export fn app_main(pid: usize) linksection(".text.main") callconv(.C) noreturn {
    kprint("app2 initial pid: {d} \n", .{pid});
    sysCalls.openTopic(1);
    var ret_buff = [_]u8{0} ** 1;
    while (true) {
        kprint("app{d} test pull \n", .{pid});
        sysCalls.popFromTopic(1, &ret_buff);
        kprint("topic pop: {d} \n", .{ret_buff[0]});
    }
}
