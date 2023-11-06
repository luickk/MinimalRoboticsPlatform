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

    var ret: usize = 0;
    var ret_buff: []u8 = undefined;
    ret_buff.ptr = @as([*]u8, @ptrCast(&ret));
    ret_buff.len = @sizeOf(@TypeOf(ret));

    var topics_interf = SharedMemTopicsInterface.init() catch |e| {
        kprint("app1 SharedMemTopicsInterface init err: {s} \n", .{@errorName(e)});
        while (true) {}
    };
    // var topics_interfaces_read = @intToPtr(*volatile [1000]usize, 0x20000000);
    while (true) {
        // kprint("topics interface read: {any} \n", .{topics_interfaces_read.*});
        const read_len: usize = topics_interf.read("height-sensor", ret_buff) catch |e| {
            kprint("app1 read err: {s} \n", .{@errorName(e)});
            while (true) {}
        };
        if (read_len < ret_buff.len) kprint("buffer partially filled {d}/ {d} bytes \n", .{ read_len, ret_buff.len });
        kprint("read: {any} \n", .{ret});
    }
}
