const std = @import("std");

const board = @import("board");
const appLib = @import("appLib");
const Mutex = appLib.Mutex;
const AppAlloc = appLib.AppAllocator;
const sysCalls = appLib.sysCalls;
const utils = appLib.utils;
const kprint = appLib.sysCalls.SysCallPrint.kprint;

var shared_thread_counter: isize = 0;

export fn app_main(pid: usize) linksection(".text.main") callconv(.C) noreturn {
    kprint("initial pid: {d} \n", .{pid});

    var app_alloc = AppAlloc.init(null) catch |e| {
        kprint("AppAlloc init error: {s}\n", .{@errorName(e)});
        while (true) {}
    };

    var mutex = Mutex.init();

    const thread_stack_mem = app_alloc.alloc(u8, board.config.mem.app_stack_size, 16) catch |e| {
        kprint("AppAlloc alloc error: {s}\n", .{@errorName(e)});
        while (true) {}
    };
    sysCalls.createThread(thread_stack_mem, testThread2, .{&mutex}) catch |e| {
        kprint("createThread init error: {s}\n", .{@errorName(e)});
        while (true) {}
    };

    const thread_stack_mem_2 = app_alloc.alloc(u8, board.config.mem.app_stack_size, 16) catch |e| {
        kprint("AppAlloc alloc error: {s}\n", .{@errorName(e)});
        while (true) {}
    };
    sysCalls.createThread(thread_stack_mem_2, testThread, .{&mutex}) catch |e| {
        kprint("createThread init error: {s}\n", .{@errorName(e)});
        while (true) {}
    };
    while (true) {}
}

pub fn testThread2(mutex: *Mutex) void {
    while (true) {
        kprint("thread2 locking.. \n", .{});
        mutex.lock() catch |e| {
            kprint("mutex lock error: {s}\n", .{@errorName(e)});
            while (true) {}
        };
        shared_thread_counter -= 1;
        kprint("thread2 accessing shared mutex protected shared resource {d} \n", .{shared_thread_counter});
        mutex.unlock();
        kprint("thread2 unlocked.. \n", .{});
    }
}

pub fn testThread(mutex: *Mutex) void {
    while (true) {
        kprint("thread1 locking.. \n", .{});
        mutex.lock() catch |e| {
            kprint("mutex lock error: {s}\n", .{@errorName(e)});
            while (true) {}
        };
        shared_thread_counter += 1;
        kprint("thread1 accessing shared mutex protected shared resource {d} \n", .{shared_thread_counter});
        mutex.unlock();
        kprint("thread1 unlocked.. \n", .{});
    }
}
