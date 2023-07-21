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
    var read_state: bool = false;
    while (true) {
        // test_counter += 1;
        // kprint("app{d} test print {d} \n", .{ pid, test_counter });

        read_state = sysCalls.readStatus(bool, "groundContact") catch |e| {
            kprint("sysCalls readStatus err: {s} \n", .{@errorName(e)});
            while (true) {}
        };
        if (!read_state) {
            sysCalls.updateStatus("groundContact", true) catch |e| {
                kprint("sysCalls updateStatus err: {s} \n", .{@errorName(e)});
            };
            kprint("status set 2 to true \n", .{});
        }
        kprint("status read 2: {any} \n", .{read_state});
    }
}
