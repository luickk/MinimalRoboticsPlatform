const periph = @import("periph");
const pl011 = periph.Pl011(.ttbr1);

const kprint = periph.uart.UartWriter(.ttbr1).kprint;
const kernelTimer = @import("kernelTimer.zig");
const utils = @import("utils");
const arm = @import("arm");
const CpuContext = arm.cpuContext.CpuContext;
const ProccessorRegMap = arm.processor.ProccessorRegMap;
const k_utils = @import("utils.zig");
const sharedKernelServices = @import("sharedKernelServices");
const Scheduler = sharedKernelServices.Scheduler;

extern var scheduler: *Scheduler;

pub const Syscall = struct {
    id: u32,
    //x0..x7 = parameters and arguments
    //x8 = SysCall id
    fn_call: *const fn (params_args: *CpuContext) void,
};

pub const sysCallTable = [_]Syscall{
    .{ .id = 0, .fn_call = &sysCallPrint },
    .{ .id = 1, .fn_call = &killProcess },
    .{ .id = 2, .fn_call = &forkProcess },
    .{ .id = 3, .fn_call = &getPid },
    .{ .id = 4, .fn_call = &killProcessRecursively },
    .{ .id = 5, .fn_call = &wait },
    .{ .id = 6, .fn_call = &createThread },
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

fn killProcess(params_args: *CpuContext) void {
    kprint("[kernel] killing task with pid: {d} \n", .{params_args.x0});
    scheduler.killProcess(params_args.x0) catch |e| {
        kprint("[panic] killProcess error: {s}\n", .{@errorName(e)});
        k_utils.panic();
    };
}

// kill a process and all its children processes
fn killProcessRecursively(params_args: *CpuContext) void {
    kprint("[kernel] killing task and children starting with pid: {d} \n", .{params_args.x0});
    scheduler.killProcessAndChildrend(params_args.x0) catch |e| {
        kprint("[panic] killProcessRecursively error: {s}\n", .{@errorName(e)});
        k_utils.panic();
    };
}

fn forkProcess(params_args: *CpuContext) void {
    kprint("[kernel] forking task with pid: {d} \n", .{params_args.x0});
    scheduler.deepForkProcess(params_args.x0) catch |e| {
        kprint("[panic] deepForkProcess error: {s}\n", .{@errorName(e)});
        k_utils.panic();
    };
}

fn getPid(params_args: *CpuContext) void {
    params_args.x0 = scheduler.getCurrentProcessPid();
}

fn wait(params_args: *CpuContext) void {
    const delay_in_nano_secs = params_args.x0;
    const delay_ticks = utils.calcTicksFromNanoSeconds(kernelTimer.getTimerFreqInHertz(), delay_in_nano_secs);
    asm volatile (
        \\mov x0, %[delay]
        \\delay_loop:
        \\subs x0, x0, #1
        \\bne delay_loop
        :
        : [delay] "r" (delay_ticks),
    );
}

fn createThread(params_args: *CpuContext) void {
    const thread_fn_ptr = @intToPtr(*fn () void, params_args.x0);
    const thread_stack = params_args.x1;
    kprint("THREAD \n", .{});
    scheduler.creatThreadForCurrentProc(thread_fn_ptr, thread_stack);
}
