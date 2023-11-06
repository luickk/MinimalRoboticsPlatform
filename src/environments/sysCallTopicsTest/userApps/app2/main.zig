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

    var ret: usize = 0;
    var ret_buff: []u8 = undefined;
    ret_buff.ptr = @as([*]u8, @ptrCast(&ret));
    ret_buff.len = @sizeOf(@TypeOf(ret));

    while (true) {
        kprint("going to wait \n", .{});
        sysCalls.waitForTopicUpdate("front-ultrasonic-proximity") catch |e| {
            kprint("syscall waitForTopicUpdate err: {s} \n", .{@errorName(e)});
            // while (true) {}
        };
        var read_len = sysCalls.popFromTopic("front-ultrasonic-proximity", ret_buff) catch |e| {
            kprint("syscall popFromTopic err: {s} \n", .{@errorName(e)});
            while (true) {}
        };
        if (read_len < ret_buff.len) kprint("buffer partially filled {d}/ {d} bytes \n", .{ read_len, ret_buff.len });
        kprint("topic pop: {any} \n", .{ret});
    }
}
