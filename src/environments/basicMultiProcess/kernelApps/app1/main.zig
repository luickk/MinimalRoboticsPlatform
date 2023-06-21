const std = @import("std");
const board = @import("board");
const arm = @import("arm");
const cpuContext = arm.cpuContext;

const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr1).kprint;

var test_counter: usize = 0;

export fn kapp_main(pid: usize) linksection(".text.main") callconv(.C) noreturn {
    kprint("kernel app1 initial pid: {d} \n", .{pid});
    while (true) {
        test_counter += 1;

        kprint("(kernel)app{d} test print {d} \n", .{ pid, test_counter });
        // if (test_counter == 40000) {
        //     test_counter += 1;
        //     // sysCalls.killProcess(1);
        //     sysCalls.killProcessRecursively(1);
        // }
    }
}

const RegValues = board.driver.secondaryInterruptConrtollerDriver.RegValues;
const RegMap = board.driver.secondaryInterruptConrtollerDriver.RegMap;
// bcm2835 interrupt controller handler for raspberry
const Bank0 = RegValues.Bank0;
const Bank1 = RegValues.Bank1;
const Bank2 = RegValues.Bank2;
pub fn irqHandler(context: *cpuContext.CpuContext) !void {
    var irq_bank_0 = try std.meta.intToEnum(Bank0, RegMap.pendingBasic.*);
    var irq_bank_1 = try std.meta.intToEnum(Bank1, RegMap.pendingIrq1.*);
    var irq_bank_2 = try std.meta.intToEnum(Bank2, RegMap.pendingIrq2.*);

    switch (irq_bank_0) {
        // One or more bits set in pending register 1
        Bank0.pending1 => {
            switch (irq_bank_1) {
                Bank1.timer1 => {
                    try board.driver.timerDriver.timerTick(context);
                    },
                else => {
                    // kprint("Not supported 1 irq num: {s} \n", .{@tagName(irq_bank_1)});
                },
            }
        },
        // One or more bits set in pending register 2
        Bank0.pending2 => {
            switch (irq_bank_2) {
                else => {
                    // kprint("Not supported bank 2 irq num: {s} \n", .{@tagName(irq_bank_0)});
                },
            }
        },
        Bank0.armTimer => {
            try board.driver.timerDriver.timerTick(context);
        },
        else => {
            // kprint("Not supported bank(neither 1/2) irq num: {d} \n", .{intController.RegMap.pendingBasic.*});
            // raspberries timers are a mess and I'm currently unsure if the Arm Generic timer
            // has an enum defined in the banks or if it's not defined through the bcm28835 system.
            try board.driver.timerDriver.timerTick(context);
        },
    }
}