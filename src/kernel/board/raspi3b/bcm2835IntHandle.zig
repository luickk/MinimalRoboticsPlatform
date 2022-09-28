const std = @import("std");
const arm = @import("arm");
const kprint = arm.uart.UartWriter(true).kprint;
const icAddr = @import("board").PeriphConfig(true).InterruptController;
const gic = arm.gicv2;
const timer = arm.timer;
const intController = arm.bcm2835IntController.InterruptController(true);

const Bank0 = intController.RegValues.Bank0;
const Bank1 = intController.RegValues.Bank1;
const Bank2 = intController.RegValues.Bank2;

pub fn irqHandler(exc: *gic.ExceptionFrame) callconv(.C) void {
    _ = exc;
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
        Bank0.armTimer => {},
        Bank0.armMailbox => {
            kprint("arm mailbox\n", .{});
        },
        Bank0.armDoorbell0 => {
            kprint("arm doorbell\n", .{});
        },
        Bank0.armDoorbell1 => {
            kprint("armm doorbell 1 b1\n", .{});
        },
        Bank0.vpu0Halted => {},
        Bank0.vpu1Halted => {},
        Bank0.illegalType0 => {},
        Bank0.illegalType1 => {},
        // One or more bits set in pending register 1
        Bank0.pending1 => {
            switch (irq_bank_1) {
                Bank1.timer1 => {
                    timer.handleTimerIrq();
                },
                else => {
                    kprint("Unknown bank 1 irq num: {s} \n", .{@tagName(irq_bank_1)});
                },
            }
        },
        // One or more bits set in pending register 2
        Bank0.pending2 => {
            switch (irq_bank_2) {
                else => {
                    kprint("Unknown bank 2 irq num: {s} \n", .{@tagName(irq_bank_2)});
                },
            }
        },
        else => {
            kprint("Unknown bank 0 irq num: {s} \n", .{@tagName(irq_bank_0)});
        },
    }
}
