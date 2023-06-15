const std = @import("std");

const board = @import("board");
const appLib = @import("appLib");
const Mutex = appLib.Mutex;
const AppAlloc = appLib.AppAllocator;
const SharedMemTopicsInterface = appLib.SharedMemTopicsInterface;
const sysCalls = appLib.sysCalls;
const kprint = appLib.sysCalls.SysCallPrint.kprint;
const utils = appLib.utils;

var test_counter: usize = 0;

var shared_thread_counter: isize = 0;
var mutex = Mutex.init();
var shared_mutex: *Mutex = &mutex;

export fn app_main(pid: usize) linksection(".text.main") callconv(.C) noreturn {
    kprint("app2 initial pid: {d} \n", .{pid});

    var topics_interf = SharedMemTopicsInterface.init() catch |e| {
        kprint("app3 SharedMemTopicsInterface init err: {s} \n", .{ @errorName(e) });
        while (true) {}
    };
    var counter: u8 = 0;
    var topics_interfaces_read = @intToPtr(*volatile [1000]usize, 0x20000000);
    while (true) {
        counter += 1;
        topics_interf.write(1, &[_]u8{counter}) catch |e| {
            kprint("app3 write err: {s} \n", .{ @errorName(e) });
            while (true) {}
        };
        kprint("pushed: {d} \n", .{counter});
        // _ = topics_interf;        
        // topics_interfaces_read[20] = 69;
        // kprint("topics interface read: {any} \n", .{topics_interfaces_read.*});
        _ = topics_interfaces_read;
    }
}
