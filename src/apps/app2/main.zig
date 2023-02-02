const std = @import("std");

const board = @import("board");
const appLib = @import("appLib");
const AppAlloc = appLib.AppAllocator;
const sysCalls = appLib.sysCalls;
const kprint = appLib.sysCalls.SysCallPrint.kprint;

var test_counter: usize = 0;

export fn app_main(pid: usize) linksection(".text.main") callconv(.C) noreturn {
    kprint("initial pid: {d} \n", .{pid});

    const _heap_start: usize = @ptrToInt(@extern(?*u8, .{ .name = "_heap_start" }) orelse {
        kprint("[panic] error reading _heap_start label\n", .{});
        while (true) {}
    });

    var alloc = AppAlloc.init(_heap_start, board.config.mem.app_vm_mem_size - _heap_start, 0x10000) catch |e| {
        kprint("[panic] AppAlloc init error: {s}\n", .{@errorName(e)});
        while (true) {}
    };

    sysCalls.createThread(&alloc, testThread, .{sysCalls.getPid()}) catch |e| {
        kprint("[panic] AppAlloc init error: {s}\n", .{@errorName(e)});
        while (true) {}
    };

    sysCalls.createThread(&alloc, testThread2, .{sysCalls.getPid()}) catch |e| {
        kprint("[panic] AppAlloc init error: {s}\n", .{@errorName(e)});
        while (true) {}
    };
    while (true) {
        test_counter += 1;
        kprint("app{d} test print {d} \n", .{ sysCalls.getPid(), test_counter });

        if (test_counter == 10000) {
            test_counter += 1;
            sysCalls.forkProcess(pid);
            // sysCalls.killProcess(pid);
        }
        // if (test_counter == 10000) {
        //     test_counter += 1;
        //     sysCalls.createThread(&alloc, &testThread) catch |e| {
        //         kprint("[panic] AppAlloc init error: {s}\n", .{@errorName(e)});
        //         while (true) {}
        //     };
        // }
    }
}

pub fn testThread(parent_pid: usize) void {
    while (true) {
        kprint("TEST THREAD 1 (daddy proc.: {d}, my pid: {d})\n", .{ parent_pid, sysCalls.getPid() });
    }
}

pub fn testThread2(parent_pid: usize) void {
    while (true) {
        kprint("TEST THREAD 2 (daddy proc.: {d}, my pid: {d}) \n", .{ parent_pid, sysCalls.getPid() });
    }
}
