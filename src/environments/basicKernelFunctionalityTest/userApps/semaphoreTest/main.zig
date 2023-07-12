const std = @import("std");
const board = @import("board");
const appLib = @import("appLib");
const AppAlloc = appLib.AppAllocator;
const sysCalls = appLib.sysCalls;
const Semaphore = appLib.Semaphore(null);
const kprint = appLib.sysCalls.SysCallPrint.kprint;

var shared_resource: isize = 0;

export fn app_main(pid: usize) linksection(".text.main") callconv(.C) noreturn {
    _ = pid;
     var app_alloc = AppAlloc.init(null) catch |e| {
        kprint("[panic] AppAlloc init error: {s}\n", .{@errorName(e)});
        while (true) {}
    };

    var test_sem = Semaphore.init(1);

    // eventual-todo => remove allcoations
    const thread_stack_mem = app_alloc.alloc(u8, board.config.mem.app_stack_size, 16) catch |e| {
        kprint("AppAlloc alloc error: {s}\n", .{@errorName(e)});
        while (true) {}
    };
    sysCalls.createThread(thread_stack_mem, testThread1, .{&test_sem}) catch |e| {
        kprint("sysCalls createThread  error: {s}\n", .{@errorName(e)});
        while (true) {}
    };

    const thread_stack_mem_2 = app_alloc.alloc(u8, board.config.mem.app_stack_size, 16) catch |e| {
        kprint("AppAlloc alloc error: {s}\n", .{@errorName(e)});
        while (true) {}
    };
    sysCalls.createThread(thread_stack_mem_2, testThread2, .{&test_sem}) catch |e| {
        kprint("sysCalls createThread error: {s}\n", .{@errorName(e)});
        while (true) {}
    };

    while (true) {}
}

fn testThread1(test_sem: *Semaphore) void {
    while (true) {
        kprint("thread1 wainting \n", .{});
        test_sem.wait(null) catch |e| {
            kprint("semaphore wait  error: {s}\n", .{@errorName(e)});
            while (true) {}
        };
        kprint("i: {d} \n", .{test_sem.i});
        shared_resource += 1;
        kprint("thread1 signaling {d} \n", .{test_sem.i});
        test_sem.signal() catch |e| {
            kprint("semaphore signal  error: {s}\n", .{@errorName(e)});
            while (true) {}
        };
        kprint("i: {d} \n", .{test_sem.i});
        // kprint("thread1 last {d} \n", .{test_sem.i});
    }
}

fn testThread2(test_sem: *Semaphore) void {
    while (true) {
        kprint("thread2 wainting {d} \n", .{test_sem.i});
        test_sem.wait(null) catch |e| {
            kprint("semaphore wait  error: {s}\n", .{@errorName(e)});
            while (true) {}
        };
        kprint("i: {d} \n", .{test_sem.i});
        shared_resource -= 1;
        kprint("thread2 signaling {d} \n", .{test_sem.i});
        test_sem.signal() catch |e| {
            kprint("semaphore signal  error: {s}\n", .{@errorName(e)});
            while (true) {}
        };
        kprint("i: {d} \n", .{test_sem.i});
        // kprint("thread2 last i: {d} \n", .{test_sem.i});
    }
}
