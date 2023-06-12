const std = @import("std");

const board = @import("board");
const appLib = @import("appLib");
const Mutex = appLib.Mutex;
const AppAlloc = appLib.AppAllocator;
const SharedMemTopicsInterface = appLib.SharedMemTopicsInterface;
const sysCalls = appLib.sysCalls;
const utils = appLib.utils;
const kprint = appLib.sysCalls.SysCallPrint.kprint;

var test_counter: usize = 0;

var shared_thread_counter: isize = 0;
var mutex = Mutex.init();
var shared_mutex: *Mutex = &mutex;

export fn app_main(pid: usize) linksection(".text.main") callconv(.C) noreturn {
    kprint("app1 initial pid: {d} \n", .{pid});
    var ret_buff = [_]u8{0} ** 1;

    var topics_interf = SharedMemTopicsInterface.init() catch |e| {
        kprint("app3 SharedMemTopicsInterface init err: {s} \n", .{ @errorName(e) });
        while (true) {}
    };
    while (true) {
        kprint("read: {any} \n", .{topics_interf.read(1, &ret_buff)});
    }
}
