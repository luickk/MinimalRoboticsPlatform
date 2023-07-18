const std = @import("std");
const board = @import("board");
const arm = @import("arm");
const cpuContext = arm.cpuContext;

const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr1).kprint;

const sharedKernelServices = @import("sharedKernelServices");
const Scheduler = sharedKernelServices.Scheduler;

pub fn threadFn(scheduler: *Scheduler) noreturn {
    _ = scheduler;
    while (true) {}
}
