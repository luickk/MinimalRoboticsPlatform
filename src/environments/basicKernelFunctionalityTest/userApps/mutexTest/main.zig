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

    var alloc = AppAlloc.init(null) catch |e| {
        kprint("AppAlloc init error: {s}\n", .{@errorName(e)});
        while (true) {}
    };

    var mutex = Mutex.init();

    sysCalls.createThread(&alloc, testThread2, .{&mutex}) catch |e| {
        kprint("createThread init error: {s}\n", .{@errorName(e)});
        while (true) {}
    };

    sysCalls.createThread(&alloc, testThread, .{&mutex}) catch |e| {
        kprint("createThread init error: {s}\n", .{@errorName(e)});
        while (true) {}
    };
    while (true) { }
}

pub fn testThread2(mutex: *Mutex) void {
    while (true) {
        kprint("thread2 locking.. \n", .{});
        mutex.lock();
        shared_thread_counter -= 1;
        kprint("thread2 accessing shared mutex protected shared resource {d} \n", .{shared_thread_counter});
        mutex.unlock();
    }
}

pub fn testThread(mutex: *Mutex) void {
    while (true) {
        kprint("thread1 locking.. \n", .{});
        mutex.lock();
        shared_thread_counter += 1;
        kprint("thread1 accessing shared mutex protected shared resource {d} \n", .{shared_thread_counter});
        mutex.unlock();
    }
}