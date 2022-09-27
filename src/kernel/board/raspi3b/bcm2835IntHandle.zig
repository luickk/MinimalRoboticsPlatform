const std = @import("std");
const periph = @import("arm");
const kprint = periph.serial.kprint;
const icAddr = @import("board").Addresses.InterruptController;
const gic = periph.gicv2;
const timer = periph.timer;

const Bank0 = icAddr.Values.Bank0;
const Bank1 = icAddr.Values.Bank1;
const Bank2 = icAddr.Values.Bank2;

pub fn irqHandler(exc: *gic.ExceptionFrame) callconv(.C) void {
    _ = exc;
    var irq_bank_0 = std.meta.intToEnum(Bank0, @intToPtr(*u32, icAddr.pendingBasic).*) catch {
        kprint("bank0 int type not found. \n", .{});
        return;
    };
    var irq_bank_1 = std.meta.intToEnum(Bank1, @intToPtr(*u32, icAddr.pendingIrq1).*) catch {
        kprint("bank1 int type not found. \n", .{});
        return;
    };
    var irq_bank_2 = std.meta.intToEnum(Bank2, @intToPtr(*u32, icAddr.pendingIrq2).*) catch {
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
