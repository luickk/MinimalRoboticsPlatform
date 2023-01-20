const periph = @import("periph");
const pl011 = periph.Pl011(.ttbr1);

const kprint = periph.uart.UartWriter(.ttbr1).kprint;
const arm = @import("arm");
const CpuContext = arm.cpuContext.CpuContext;
const ProccessorRegMap = arm.processor.ProccessorRegMap;
const k_utils = @import("utils.zig");
const sharedKernelServices = @import("sharedKernelServices");
const Scheduler = sharedKernelServices.Scheduler;

extern var scheduler: *Scheduler;

//x0..x7 = parameters and arguments
//x8 = SysCall id
pub const ParamArgRegs = struct {
    x0: usize,
    x1: usize,
    x2: usize,
    x3: usize,
    x4: usize,
    x5: usize,
    x6: usize,
    x7: usize,
};

pub const Syscall = struct {
    id: u32,
    fn_call: *const fn (params_args: ParamArgRegs) void,
};

pub const sysCallTable = [_]Syscall{
    .{ .id = 0, .fn_call = &sysCallPrint },
    .{ .id = 1, .fn_call = &exitProcess },
    .{ .id = 2, .fn_call = &forkProcess },
};

fn sysCallPrint(params_args: ParamArgRegs) void {
    // arguments for the function from the saved interrupt context
    const data = params_args.x0;
    const len = params_args.x1;
    var sliced_data: []u8 = undefined;
    sliced_data.len = len;
    sliced_data.ptr = @intToPtr([*]u8, data);
    // kprint("data: {s} \n", .{sliced_data});
    pl011.write(sliced_data);
}

fn exitProcess(params_args: ParamArgRegs) void {
    kprint("[kernel] killing task with pid: {d} \n", .{params_args.x0});
    scheduler.killProcess(params_args.x0) catch |e| {
        kprint("[panic] killProcess error: {s}\n", .{@errorName(e)});
        k_utils.panic();
    };
}

fn forkProcess(params_args: ParamArgRegs) void {
    kprint("[kernel] forking task with pid: {d} \n", .{params_args.x0});
    scheduler.deepForkProcess(params_args.x0) catch |e| {
        kprint("[panic] deepForkProcess error: {s}\n", .{@errorName(e)});
        k_utils.panic();
    };
}
