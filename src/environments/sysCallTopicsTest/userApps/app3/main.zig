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
    kprint("app3 initial pid: {d} \n", .{pid});

    var ret: usize = 0;
    var ret_buff: []u8 = undefined;
    ret_buff.ptr = @ptrCast([*]u8, &ret);
    ret_buff.len = @sizeOf(@TypeOf(ret));

    var topics_interf = SharedMemTopicsInterface.init() catch |e| {
        kprint("app3 SharedMemTopicsInterface init err: {s} \n", .{@errorName(e)});
        while (true) {}
    };
    while (true) {
        var read_len = topics_interf.read("front-ultrasonic-proximity", ret_buff) catch |e| {
            kprint("app3 SharedMemTopicsInterface read err: {s} \n", .{@errorName(e)});
            while (true) {}
        };
        if (read_len < ret_buff.len) kprint("buffer partially filled {d}/ {d} bytes \n", .{ read_len, ret_buff.len });
        kprint("SharedMemTopicsInterface read: {any} \n", .{ret});
        // _ = topics_interf;
        // _ = ret_buff;
    }
}
