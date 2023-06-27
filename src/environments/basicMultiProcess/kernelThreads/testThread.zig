const std = @import("std");
const board = @import("board");
const arm = @import("arm");
const cpuContext = arm.cpuContext;

const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr1).kprint;


const sharedKernelServices = @import("sharedKernelServices");
const Scheduler = sharedKernelServices.Scheduler;

pub fn threadFn(scheduler: *Scheduler) noreturn {
    var i: usize = 0;
    while (i < 10000) : (i += 1) {
        kprint("kernel test thread {d} \n", .{i});
    }
    scheduler.exitTask() catch |e| {
        kprint("[error] exitTask error: {s} \n", .{@errorName(e)});
        while(true) {}  
    };
}
