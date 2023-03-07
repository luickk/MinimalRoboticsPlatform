const std = @import("std");
const arm = @import("arm");
const cpuContext = arm.cpuContext;
const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr1).kprint;
const icCfg = @import("board").PeriphConfig(.ttbr1).InterruptController;
const gic = arm.gicv2;
const timer = @import("timer.zig");
const intController = arm.bcm2835IntController.InterruptController(.ttbr1);

const Bank0 = intController.RegValues.Bank0;
const Bank1 = intController.RegValues.Bank1;
const Bank2 = intController.RegValues.Bank2;

pub fn irqHandler(context: *cpuContext.CpuContext) callconv(.C) void {
    var irq_bank_0 = std.meta.intToEnum(Bank0, intController.RegMap.pendingBasic.*) catch {
        kprint("bank0 int type not found. \n", .{});
        return;
    };
    var irq_bank_1 = std.meta.intToEnum(Bank1, intController.RegMap.pendingIrq1.*) catch {
        kprint("bank1 int type not found. \n", .{});
        return;
    };
    var irq_bank_2 = std.meta.intToEnum(Bank2, intController.RegMap.pendingIrq2.*) catch {
        kprint("bank2 int type not found. \n", .{});
        return;
    };

    switch (irq_bank_0) {
        // One or more bits set in pending register 1
        Bank0.pending1 => {
            switch (irq_bank_1) {
                Bank1.timer1 => {
                    timer.handleTimerIrq(context) catch |e| {
                        kprint("[panic] generic timer error: {s} \n", .{@errorName(e)});
                        while (true) {}
                    };
                },
                else => {
                    kprint("Not supported 1 irq num: {s} \n", .{@tagName(irq_bank_1)});
                },
            }
        },
        // One or more bits set in pending register 2
        Bank0.pending2 => {
            switch (irq_bank_2) {
                else => {
                    kprint("Not supported bank 2 irq num: {s} \n", .{@tagName(irq_bank_0)});
                },
            }
        },
        else => {
            kprint("Not supported bank(neither 1/2) irq num: {s} \n", .{@tagName(irq_bank_0)});
        },
    }
}
