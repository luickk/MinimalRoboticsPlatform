const std = @import("std");
const board = @import("board");
const alignForward = std.mem.alignForward;
const AppAllocator = @import("AppAllocator.zig").AppAllocator;
const Mutex = @import("Mutex.zig").Mutex;
const utils = @import("utils");

const Error = error{
    SleepDelayTooShortForScheduler,
};

pub const SysCallPrint = struct {
    const Self = @This();
    pub const Writer = std.io.Writer(*Self, error{}, appendWrite);

    pub fn writer(self: *Self) Writer {
        return .{ .context = self };
    }

    fn callKernelPrint(data: [*]const u8, len: usize) void {
        asm volatile (
        // args
            \\mov x0, %[data_addr]
            \\mov x1, %[len]
            // sys call id
            \\mov x8, #0
            \\svc #0
            :
            : [data_addr] "r" (@ptrToInt(data)),
              [len] "r" (len),
            : "x0", "x1", "x8"
        );
        // asm volatile ("brk 0xdead");
    }
    /// Same as `append` except it returns the number of bytes written, which is always the same
    /// as `m.len`. The purpose of this function existing is to match `std.io.Writer` API.
    fn appendWrite(self: *Self, data: []const u8) error{}!usize {
        _ = self;
        // asm volatile ("brk 0xdead");
        callKernelPrint(data.ptr, data.len);
        return data.len;
    }

    pub fn kprint(comptime print_string: []const u8, args: anytype) void {
        var tempW: SysCallPrint = undefined;
        std.fmt.format(tempW.writer(), print_string, args) catch |err| {
            @panic(err);
        };
    }
};

pub fn killTask(pid: usize) noreturn {
    asm volatile (
    // args
        \\mov x0, %[pid]
        // sys call id
        \\mov x8, #1
        \\svc #0
        :
        : [pid] "r" (pid),
        : "x0", "x8"
    );
    while (true) {}
}

// pub fn forkProcess(pid: usize) void {
//     asm volatile (
//     // args
//         \\mov x0, %[pid]
//         // sys call id
//         \\mov x8, #2
//         \\svc #0
//         :
//         : [pid] "r" (pid),
//         : "x0", "x8"
//     );
// }

pub fn getPid() usize {
    return asm (
        \\mov x8, #3
        \\svc #0
        \\mov %[curr], x0
        : [curr] "=r" (-> usize),
        :
        : "x0", "x8"
    );
}

pub fn killTaskRecursively(starting_pid: usize) void {
    asm volatile (
    // args
        \\mov x0, %[pid]
        // sys call id
        \\mov x8, #4
        \\svc #0
        :
        : [pid] "r" (starting_pid),
        : "x0", "x8"
    );
}

// creates thread for current process
pub fn createThread(thread_stack_mem: []u8, thread_fn: anytype, args: anytype) !void {
    var thread_stack_start: []u8 = undefined;
    thread_stack_start.ptr = @intToPtr([*]u8, @ptrToInt(thread_stack_mem.ptr) + thread_stack_mem.len);
    thread_stack_start.len = thread_stack_mem.len;
    var arg_mem: []const u8 = undefined;
    arg_mem.ptr = @ptrCast([*]const u8, @alignCast(1, &args));
    arg_mem.len = @sizeOf(@TypeOf(args));

    std.mem.copy(u8, thread_stack_start, arg_mem);

    asm volatile (
    // args
        \\mov x0, %[entry_fn_ptr]
        \\mov x1, %[thread_stack]
        \\mov x2, %[args_addr]
        \\mov x3, %[thread_fn_ptr]
        // sys call id
        \\mov x8, #6
        \\svc #0
        :
        : [entry_fn_ptr] "r" (@ptrToInt(&(ThreadInstance(thread_fn, @TypeOf(args)).threadEntry))),
          [thread_stack] "r" (@ptrToInt(thread_stack_start.ptr) - alignForward(@sizeOf(@TypeOf(args)), 16)),
          [args_addr] "r" (@ptrToInt(thread_stack_start.ptr)),
          [thread_fn_ptr] "r" (@ptrToInt(&thread_fn)),
        : "x0", "x1", "x2", "x3", "x8"
    );
}

// provides a generic entry function (generic in regard to the thread and argument function since @call builtin needs them to properly invoke the thread start)
fn ThreadInstance(comptime thread_fn: anytype, comptime Args: type) type {
    const ThreadFn = @TypeOf(thread_fn);
    return struct {
        fn threadEntry(entry_fn: *ThreadFn, entry_args: *Args) callconv(.C) void {
            @call(.{ .modifier = .auto }, entry_fn, entry_args.*);
        }
    };
}

pub fn sleep(delay_in_nano_secs: usize) !void {
    const delay_in_hertz = delay_in_nano_secs * 1000000000;
    const delay_sched_intervals = board.config.scheduler_freq_in_hertz / delay_in_hertz;
    if (board.config.scheduler_freq_in_hertz < delay_in_hertz) return Error.SleepDelayTooShortForScheduler;
    asm volatile (
    // args
        \\mov x0, %[delay]
        // sys call id
        \\mov x8, #7
        \\svc #0
        :
        : [delay] "r" (delay_sched_intervals),
        : "x0", "x8"
    );
}

pub fn haltProcess(pid: usize) void {
    asm volatile (
    // args
        \\mov x0, %[pid]
        // sys call id
        \\mov x8, #8
        \\svc #0
        :
        : [pid] "r" (pid),
        : "x0", "x8"
    );
}

pub fn continueProcess(pid: usize) void {
    asm volatile (
    // args
        \\mov x0, %[pid]
        // sys call id
        \\mov x8, #9
        \\svc #0
        :
        : [pid] "r" (pid),
        : "x0", "x8"
    );
}

pub fn closeTopic(id: usize) void {
    asm volatile (
    // args
        \\mov x0, %[id]
        // sys call id
        \\mov x8, #10
        \\svc #0
        :
        : [id] "r" (id),
        : "x0", "x8"
    );
}

pub fn openTopic(id: usize) void {
    asm volatile (
    // args
        \\mov x0, %[id]
        // sys call id
        \\mov x8, #11
        \\svc #0
        :
        : [id] "r" (id),
        : "x0", "x8"
    );
}

pub fn pushToTopic(id: usize, data: []u8) void {
    const data_ptr: usize = @ptrToInt(data.ptr);
    const data_len = data.len;
    asm volatile (
    // args
        \\mov x0, %[id]
        \\mov x1, %[data_ptr]
        \\mov x2, %[data_len]
        // sys call id
        \\mov x8, #12
        \\svc #0
        :
        : [id] "r" (id),
          [data_ptr] "r" (data_ptr),
          [data_len] "r" (data_len),
        : "x0", "x1", "x2", "x8"
    );
}

pub fn popFromTopic(id: usize, ret_buff: []u8) void {
    asm volatile (
    // args
        \\mov x0, %[id]
        \\mov x1, %[data_len]
        \\mov x2, %[ret_buff]
        // sys call id
        \\mov x8, #13
        \\svc #0
        :
        : [id] "r" (id),
          [data_len] "r" (ret_buff.len),
          [ret_buff] "r" (@ptrToInt(ret_buff.ptr)),
        : "x0", "x1", "x2", "x8"
    );
}

pub fn waitForTopicUpdate(topic_id: usize) void {
    const pid = getPid();
    asm volatile (
    // args
        \\mov x0, %[topic_id]
        \\mov x1, %[pid]
        // sys call id
        \\mov x8, #14
        \\svc #0
        :
        : [topic_id] "r" (topic_id),
          [pid] "r" (pid),
        : "x0", "x1", "x8"
    );
}


pub fn increaseCurrTaskPreemptCounter() void {
    asm volatile (
    // args
        // sys call id
        \\mov x8, #15
        \\svc #0
        :
        :
        : "x8"
    );
}



pub fn decreaseCurrTaskPreemptCounter() void {
    asm volatile (
    // args
        // sys call id
        \\mov x8, #16
        \\svc #0
        :
        :
        : "x8"
    );
}
