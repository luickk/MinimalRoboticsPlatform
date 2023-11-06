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
        kprint("app2 SharedMemTopicsInterface init err: {s} \n", .{@errorName(e)});
        while (true) {}
    };
    var counter: usize = 0;

    var payload: []u8 = undefined;
    payload.ptr = @as([*]u8, @ptrCast(&counter));
    payload.len = @sizeOf(@TypeOf(counter));
    while (true) {
        counter += 1;
        const written_data = topics_interf.write("height-sensor", payload) catch |e| {
            kprint("app2 write err: {s} \n", .{@errorName(e)});
            while (true) {}
        };
        if (written_data < payload.len) kprint("buffer partially filled {d}/ {d} bytes \n", .{ written_data, payload.len });
        kprint("pushed: {d} \n", .{counter});
    }
}
