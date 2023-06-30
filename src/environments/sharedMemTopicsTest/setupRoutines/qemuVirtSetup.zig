const std = @import("std");
const board = @import("board");
const arm = @import("arm");
const cpuContext = arm.cpuContext;

const ProccessorRegMap = arm.processor.ProccessorRegMap;

const gic = arm.gicv2.Gic(.ttbr1);
const InterruptIds = gic.InterruptIds;

const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr1).kprint;


const sharedKernelServices = @import("sharedKernelServices");
const Scheduler = sharedKernelServices.Scheduler;

pub fn qemuVirtSetup(scheduler: *Scheduler) void {
    _ = scheduler;

    gic.init() catch |e| {
        kprint("[panic] gic init error: {s}\n", .{@errorName(e)});
        while(true) {}
    };

    gic.Gicd.gicdConfig(InterruptIds.non_secure_physical_timer, 0x2) catch |e| {
        kprint("[panic] gicd gicdConfig error: {s}\n", .{@errorName(e)});
        while(true) {}
    };
    gic.Gicd.gicdSetPriority(InterruptIds.non_secure_physical_timer, 0) catch |e| {
        kprint("[panic] gicd setPriority error: {s}\n", .{@errorName(e)});
        while(true) {}
    };
    gic.Gicd.gicdSetTarget(InterruptIds.non_secure_physical_timer, 1) catch |e| {
        kprint("[panic] gicd setTarget error: {s}\n", .{@errorName(e)});
        while(true) {}
    };

    gic.Gicd.gicdClearPending(InterruptIds.non_secure_physical_timer) catch |e| {
        kprint("[panic] gicd clearPending error: {s}\n", .{@errorName(e)});
        while(true) {}
    };

    gic.Gicd.gicdEnableInt(InterruptIds.non_secure_physical_timer) catch |e| {
        kprint("[panic] gicdEnableInt address calc error: {s}\n", .{@errorName(e)});
        while(true) {}
    };

    ProccessorRegMap.DaifReg.setDaifClr(.{
        .debug = true,
        .serr = true,
        .irqs = true,
        .fiqs = true,
    });
}