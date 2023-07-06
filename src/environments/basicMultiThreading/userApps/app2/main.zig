const std = @import("std");

const board = @import("board");
const appLib = @import("appLib");
const Mutex = appLib.Mutex;
const AppAlloc = appLib.AppAllocator;
const sysCalls = appLib.sysCalls;
const utils = appLib.utils;
const kprint = appLib.sysCalls.SysCallPrint.kprint;

export fn app_main(pid: usize) linksection(".text.main") callconv(.C) noreturn {
    kprint("initial pid: {d} \n", .{pid});

    var app_alloc = AppAlloc.init(null) catch |e| {
        kprint("AppAlloc init error: {s}\n", .{@errorName(e)});
        while (true) {}
    };

    const thread_stack_mem = app_alloc.alloc(u8, board.config.mem.app_stack_size, 16) catch |e| {
        kprint("AppAlloc alloc error: {s}\n", .{@errorName(e)});
        while (true) {}
    };
    sysCalls.createThread(thread_stack_mem, testThread, .{sysCalls.getPid()}) catch |e| {
        kprint("AppAlloc init error: {s}\n", .{@errorName(e)});
        while (true) {}
    };

    const thread_stack_mem_2 = app_alloc.alloc(u8, board.config.mem.app_stack_size, 16) catch |e| {
        kprint("AppAlloc alloc error: {s}\n", .{@errorName(e)});
        while (true) {}
    };
    sysCalls.createThread(thread_stack_mem_2, testThread2, .{sysCalls.getPid()}) catch |e| {
        kprint("AppAlloc init error: {s}\n", .{@errorName(e)});
        while (true) {}
    };
    while (true) {
        kprint("multithreading test counter \n", .{});
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
