const std = @import("std");
const periph = @import("periph");
const pl011 = periph.Pl011(.ttbr1);

const kprint = periph.uart.UartWriter(.ttbr1).kprint;
const utils = @import("utils");
const board = @import("board");
const arm = @import("arm");
const CpuContext = arm.cpuContext.CpuContext;
const ProccessorRegMap = arm.processor.ProccessorRegMap;
const k_utils = @import("utils.zig");

const sharedKernelServices = @import("sharedKernelServices");
const StatusControl = sharedKernelServices.StatusControl;
const Scheduler = sharedKernelServices.Scheduler;
const Topics = sharedKernelServices.SysCallsTopicsInterface;

const Semaphore = sharedKernelServices.KSemaphore;

// global user required since the scheduler calls are invoked via svc
extern var scheduler: *Scheduler;
extern var status_control: *StatusControl;
extern var topics: *Topics;

pub const Syscall = struct {
    id: u32,
    //x0..x7 = parameters and arguments (if x0 is negative it's an errno)
    //x8 = SysCall id
    fn_call: *const fn (params_args: *CpuContext) void,
};

pub const sysCallTable = [_]Syscall{
    .{ .id = 0, .fn_call = &sysCallPrint },
    .{ .id = 1, .fn_call = &killTask },
    // .{ .id = 2, .fn_call = &xxx },
    .{ .id = 3, .fn_call = &getPid },
    .{ .id = 4, .fn_call = &killTaskRecursively },
    // .{ .id = 5, .fn_call = &xxx },
    .{ .id = 6, .fn_call = &createThread },
    .{ .id = 7, .fn_call = &sleep },
    .{ .id = 8, .fn_call = &haltProcess },
    .{ .id = 9, .fn_call = &continueProcess },
    // .{ .id = 10, .fn_call = &xxx },
    // .{ .id = 11, .fn_call = &xxx },
    .{ .id = 12, .fn_call = &pushToTopic },
    .{ .id = 13, .fn_call = &popFromTopic },
    .{ .id = 14, .fn_call = &waitForTopicUpdate },
    .{ .id = 15, .fn_call = &increaseCurrTaskPreemptCounter },
    .{ .id = 16, .fn_call = &decreaseCurrTaskPreemptCounter },
    .{ .id = 17, .fn_call = &updateStatus },
    .{ .id = 18, .fn_call = &readStatus },
};

fn sysCallPrint(params_args: *CpuContext) void {
    // arguments for the function from the saved interrupt context
    const data = params_args.x0;
    const len = params_args.x1;
    var sliced_data: []u8 = undefined;
    sliced_data.len = len;
    sliced_data.ptr = @intToPtr([*]u8, data);
    pl011.write(sliced_data);
}

fn killTask(params_args: *CpuContext) void {
    kprint("[kernel] killing task with pid: {d} \n", .{params_args.x0});
    scheduler.killTask(@truncate(u16, params_args.x0)) catch |e| {
        kprint("[panic] killTask error: {s}\n", .{@errorName(e)});
        @ptrCast(*isize, &params_args.x0).* = 0 - @intCast(isize, @errorToInt(e));
        return;
    };
}

// kill a process and all its children processes
fn killTaskRecursively(params_args: *CpuContext) void {
    kprint("[kernel] killing task and children starting with pid: {d} \n", .{params_args.x0});
    scheduler.killTaskAndChildrend(@truncate(u16, params_args.x0)) catch |e| {
        kprint("[panic] killTaskRecursively error: {s}\n", .{@errorName(e)});
        @ptrCast(*isize, &params_args.x0).* = 0 - @intCast(isize, @errorToInt(e));
        return;
    };
}

// fn forkProcess(params_args: *CpuContext) void {
//     kprint("[kernel] forking task with pid: {d} \n", .{params_args.x0});
//     scheduler.deepForkProcess(params_args.x0) catch |e| {
//         kprint("[panic] deepForkProcess error: {s}\n", .{@errorName(e)});
//         k_utils.panic();
//     };
// }

fn getPid(params_args: *CpuContext) void {
    params_args.x0 = scheduler.getCurrentProcessPid();
}

fn createThread(params_args: *CpuContext) void {
    const entry_fn_ptr = @intToPtr(*anyopaque, params_args.x0);
    const thread_stack = params_args.x1;
    const args = @intToPtr(*anyopaque, params_args.x2);
    const thread_fn_ptr = @intToPtr(*anyopaque, params_args.x3);
    scheduler.createThreadFromCurrentProcess(entry_fn_ptr, thread_fn_ptr, thread_stack, args) catch |e| {
        kprint("[panic] createThreadFromCurrentProcess error: {s}\n", .{@errorName(e)});
        @ptrCast(*isize, &params_args.x0).* = 0 - @intCast(isize, @errorToInt(e));
        return;
    };
}

fn sleep(params_args: *CpuContext) void {
    const delay_in_sched_inter = params_args.x0;
    scheduler.setProcessAsleep(scheduler.getCurrentProcessPid(), delay_in_sched_inter, params_args) catch |e| {
        kprint("[panic] setProcessAsleep error: {s}\n", .{@errorName(e)});
        @ptrCast(*isize, &params_args.x0).* = 0 - @intCast(isize, @errorToInt(e));
        return;
    };
}

fn haltProcess(params_args: *CpuContext) void {
    const pid: u16 = @truncate(u16, params_args.x0);
    scheduler.setProcessState(pid, .halted, params_args) catch |e| {
        kprint("Scheduler setProcessState err: {s}\n", .{@errorName(e)});
        @ptrCast(*isize, &params_args.x0).* = 0 - @intCast(isize, @errorToInt(e));
        return;
    };
}

fn continueProcess(params_args: *CpuContext) void {
    const pid: u16 = @truncate(u16, params_args.x0);
    scheduler.setProcessState(pid, .running, params_args) catch |e| {
        kprint("Scheduler setProcessState err: {s}\n", .{@errorName(e)});
        @ptrCast(*isize, &params_args.x0).* = 0 - @intCast(isize, @errorToInt(e));
        return;
    };
}

fn increaseCurrTaskPreemptCounter(params_args: *CpuContext) void {
    _ = params_args;
    scheduler.current_task.preempt_count += 1;
}

fn decreaseCurrTaskPreemptCounter(params_args: *CpuContext) void {
    _ = params_args;
    scheduler.current_task.preempt_count -= 1;
}

fn pushToTopic(params_args: *CpuContext) void {
    const id = params_args.x0;
    const data_ptr = params_args.x1;
    const data_len = params_args.x2;
    // kprint("...: {any}\n", .{params_args.x0});
    params_args.x0 = topics.write(id, @intToPtr(*u8, data_ptr), data_len) catch |e| {
        kprint("Topics write error: {s}\n", .{@errorName(e)});
        @ptrCast(*isize, &params_args.x0).* = 0 - @intCast(isize, @errorToInt(e));
        return;
    };
}

fn popFromTopic(params_args: *CpuContext) void {
    const id = params_args.x0;
    const data_len = params_args.x1;
    var ret_buff = @intToPtr([]u8, params_args.x2);
    ret_buff.len = data_len;
    params_args.x0 = topics.read(id, ret_buff) catch |e| {
        kprint("Topics popFromTopic error: {s}\n", .{@errorName(e)});
        @ptrCast(*isize, &params_args.x0).* = 0 - @intCast(isize, @errorToInt(e));
        return;
    };
}

fn waitForTopicUpdate(params_args: *CpuContext) void {
    const topic_id = params_args.x0;
    const pid: u16 = @truncate(u16, params_args.x1);
    topics.makeTaskWait(topic_id, pid, params_args) catch |e| {
        kprint("Topics waitForTopicUpdate error: {s}\n", .{@errorName(e)});
        @ptrCast(*isize, &params_args.x0).* = 0 - @intCast(isize, @errorToInt(e));
        return;
    };
}

fn updateStatus(params_args: *CpuContext) void {
    const status_id = @intCast(u16, params_args.x0);
    const val_addr = params_args.x1;
    status_control.updateStatusRaw(status_id, val_addr) catch |e| {
        kprint("StatusControl updateStatus error: {s}\n", .{@errorName(e)});
        @ptrCast(*isize, &params_args.x0).* = 0 - @intCast(isize, @errorToInt(e));
        return;
    };
}

fn readStatus(params_args: *CpuContext) void {
    const status_id = @intCast(u16, params_args.x0);
    var ret_buff = params_args.x1;
    status_control.readStatusRaw(status_id, ret_buff) catch |e| {
        kprint("StatusControl readRaw error: {s}\n", .{@errorName(e)});
        @ptrCast(*isize, &params_args.x0).* = 0 - @intCast(isize, @errorToInt(e));
        return;
    };
}
