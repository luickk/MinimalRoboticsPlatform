const std = @import("std");
const board = @import("board");
const env = @import("environment");
const alignForward = std.mem.alignForward;
const AppAllocator = @import("AppAllocator.zig").AppAllocator;
const Mutex = @import("Mutex.zig").Mutex;
const utils = @import("utils");

const sysCalls = @import("userSysCallInterface.zig");
const kprint = sysCalls.SysCallPrint.kprint;

const Error = error{ SleepDelayTooShortForScheduler, SysCallError, StatusInterfaceMissmatch, StatusTypeMissmatch };

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
            : [data_addr] "r" (@intFromPtr(data)),
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

fn checkForError(x0: usize) !usize {
    if (@as(isize, @intCast(x0)) < 0) {
        return Error.SysCallError;
    }
    return x0;
}

pub fn getPid() !u16 {
    const ret = asm (
        \\mov x8, #3
        \\svc #0
        \\mov %[curr], x0
        : [curr] "=r" (-> usize),
        :
        : "x0", "x8"
    );
    return @as(u16, @truncate(try checkForError(ret)));
}

pub fn killTaskRecursively(starting_pid: usize) !void {
    const ret = asm volatile (
    // args
        \\mov x0, %[pid]
        // sys call id
        \\mov x8, #4
        \\svc #0
        \\mov %[ret], x0
        : [ret] "=r" (-> usize),
        : [pid] "r" (starting_pid),
        : "x0", "x8"
    );
    _ = try checkForError(ret);
}

// creates thread for current process
pub fn createThread(thread_stack_mem: []u8, thread_fn: anytype, args: anytype) !void {
    var thread_stack_start: []u8 = undefined;
    thread_stack_start.ptr = @as([*]u8, @ptrFromInt(@intFromPtr(thread_stack_mem.ptr) + thread_stack_mem.len));
    thread_stack_start.len = thread_stack_mem.len;
    var arg_mem: []const u8 = undefined;
    arg_mem.ptr = @as([*]const u8, @ptrCast(@alignCast(&args)));
    arg_mem.len = @sizeOf(@TypeOf(args));

    std.mem.copy(u8, thread_stack_start, arg_mem);

    const ret = asm volatile (
    // args
        \\mov x0, %[entry_fn_ptr]
        \\mov x1, %[thread_stack]
        \\mov x2, %[args_addr]
        \\mov x3, %[thread_fn_ptr]
        // sys call id
        \\mov x8, #6
        \\svc #0
        \\mov %[ret], x0
        : [ret] "=r" (-> usize),
        : [entry_fn_ptr] "r" (@intFromPtr(&(ThreadInstance(thread_fn, @TypeOf(args)).threadEntry))),
          [thread_stack] "r" (@intFromPtr(thread_stack_start.ptr) - alignForward(usize, @sizeOf(@TypeOf(args)), 16)),
          [args_addr] "r" (@intFromPtr(thread_stack_start.ptr)),
          [thread_fn_ptr] "r" (@intFromPtr(&thread_fn)),
        : "x0", "x1", "x2", "x3", "x8"
    );
    _ = try checkForError(ret);
}

// provides a generic entry function (generic in regard to the thread and argument function since @call builtin needs them to properly invoke the thread start)
fn ThreadInstance(comptime thread_fn: anytype, comptime Args: type) type {
    const ThreadFn = @TypeOf(thread_fn);
    return struct {
        fn threadEntry(entry_fn: *ThreadFn, entry_args: *Args) callconv(.C) void {
            @call(.auto, entry_fn, entry_args.*);
        }
    };
}

pub fn sleep(delay_in_nano_secs: usize) !void {
    const delay_in_hertz = try std.math.divTrunc(usize, delay_in_nano_secs, std.time.ns_per_s);
    const delay_sched_intervals = board.config.scheduler_freq_in_hertz / delay_in_hertz;
    if (board.config.scheduler_freq_in_hertz < delay_in_hertz) return Error.SleepDelayTooShortForScheduler;
    const ret = asm volatile (
    // args
        \\mov x0, %[delay]
        // sys call id
        \\mov x8, #7
        \\svc #0
        \\mov %[ret], x0
        : [ret] "=r" (-> usize),
        : [delay] "r" (delay_sched_intervals),
        : "x0", "x8"
    );
    _ = try checkForError(ret);
}

pub fn haltProcess(pid: usize) !void {
    const ret = asm volatile (
    // args
        \\mov x0, %[pid]
        // sys call id
        \\mov x8, #8
        \\svc #0
        \\mov %[ret], x0
        : [ret] "=r" (-> usize),
        : [pid] "r" (pid),
        : "x0", "x8"
    );
    _ = try checkForError(ret);
}

pub fn continueProcess(pid: usize) !void {
    const ret = asm volatile (
    // args
        \\mov x0, %[pid]
        // sys call id
        \\mov x8, #9
        \\svc #0
        \\mov %[ret], x0
        : [ret] "=r" (-> usize),
        : [pid] "r" (pid),
        : "x0", "x8"
    );
    _ = try checkForError(ret);
}

pub fn pushToTopic(comptime name: []const u8, data: []u8) !usize {
    const status = try env.env_config.getStatusInfo(name);
    if (status.type != null) return Error.StatusInterfaceMissmatch;

    const data_ptr: usize = @intFromPtr(data.ptr);
    const data_len = data.len;
    const ret = asm volatile (
    // args
        \\mov x0, %[id]
        \\mov x1, %[data_ptr]
        \\mov x2, %[data_len]
        // sys call id
        \\mov x8, #12
        \\svc #0
        \\mov %[ret], x0
        : [ret] "=r" (-> usize),
        : [id] "r" (status.id),
          [data_ptr] "r" (data_ptr),
          [data_len] "r" (data_len),
        : "x0", "x1", "x2", "x8"
    );
    return checkForError(ret);
}

pub fn popFromTopic(comptime name: []const u8, ret_buff: []u8) !usize {
    const status = try env.env_config.getStatusInfo(name);
    if (status.type != null) return Error.StatusInterfaceMissmatch;

    const ret = asm volatile (
    // args
        \\mov x0, %[id]
        \\mov x1, %[data_len]
        \\mov x2, %[ret_buff]
        // sys call id
        \\mov x8, #13
        \\svc #0
        \\mov %[ret], x0
        : [ret] "=r" (-> usize),
        : [id] "r" (status.id),
          [data_len] "r" (ret_buff.len),
          [ret_buff] "r" (@intFromPtr(ret_buff.ptr)),
        : "x0", "x1", "x2", "x8"
    );
    return checkForError(ret);
}

pub fn waitForTopicUpdate(comptime name: []const u8) !void {
    const status = try env.env_config.getStatusInfo(name);
    const pid = getPid();
    const ret = asm volatile (
    // args
        \\mov x0, %[topic_id]
        \\mov x1, %[pid]
        // sys call id
        \\mov x8, #14
        \\svc #0
        \\mov %[ret], x0
        : [ret] "=r" (-> usize),
        : [topic_id] "r" (status.id),
          [pid] "r" (pid),
        : "x0", "x1", "x8"
    );
    _ = try checkForError(ret);
}

pub fn increaseCurrTaskPreemptCounter() !void {
    const ret = asm volatile (
    // args
    // sys call id
        \\mov x8, #15
        \\svc #0
        \\mov %[ret], x0
        : [ret] "=r" (-> usize),
        :
        : "x8"
    );
    _ = try checkForError(ret);
}

pub fn decreaseCurrTaskPreemptCounter() !void {
    const ret = asm volatile (
    // args
    // sys call id
        \\mov x8, #16
        \\svc #0
        \\mov %[ret], x0
        : [ret] "=r" (-> usize),
        :
        : "x8"
    );
    _ = try checkForError(ret);
}

pub fn updateStatus(comptime name: []const u8, value: anytype) !void {
    const status = try env.env_config.getStatusInfo(name);
    if (status.type == null) return Error.StatusInterfaceMissmatch;
    if (@TypeOf(value) != status.type.?) return Error.StatusTypeMissmatch;
    const ret = asm volatile (
    // args
    // sys call id
        \\mov x0, %[id]
        \\mov x1, %[val_addr]
        \\mov x8, #17
        \\svc #0
        \\mov %[ret], x0
        : [ret] "=r" (-> usize),
        : [id] "r" (status.id),
          [val_addr] "r" (&value),
        : "x8"
    );
    _ = try checkForError(ret);
}
pub fn readStatus(comptime T: type, comptime name: []const u8) !T {
    const status = try env.env_config.getStatusInfo(name);
    if (status.type == null) return Error.StatusInterfaceMissmatch;
    if (T != status.type.?) return Error.StatusTypeMissmatch;

    var ret_buff: status.type.? = undefined;
    const ret = asm volatile (
    // args
        \\mov x0, %[id]
        \\mov x1, %[ret_buff]
        // sys call id
        \\mov x8, #18
        \\svc #0
        \\mov %[ret], x0
        : [ret] "=r" (-> usize),
        : [id] "r" (status.id),
          [ret_buff] "r" (@intFromPtr(&ret_buff)),
        : "x0", "x1", "x8"
    );
    _ = try checkForError(ret);
    return ret_buff;
}
