const std = @import("std");
const periph = @import("peripherals");
const kprint = periph.serial.kprint;
const icAddr = @import("board").Addresses.InterruptController;
const iC = periph.intController;
const timer = periph.timer;

const Bank0 = icAddr.Values.Bank0;
const Bank1 = icAddr.Values.Bank1;
const Bank2 = icAddr.Values.Bank2;

pub fn irqHandler(exc: *iC.ExceptionFrame) callconv(.C) void {

    // std intToEnum instead of build in in order to catch err
    var int_type = std.meta.intToEnum(iC.ExceptionType, exc.int_type) catch {
        kprint("int type not found \n", .{});
        return;
    };
    switch (int_type) {
        iC.ExceptionType.el1Sync => {
            var iss = @truncate(u25, exc.esr_el1);
            var il = @truncate(u1, exc.esr_el1 >> 25);
            var ec = @truncate(u6, exc.esr_el1 >> 26);
            var iss2 = @truncate(u5, exc.esr_el1 >> 32);
            _ = iss;
            _ = iss2;

            var ec_en = std.meta.intToEnum(iC.ExceptionClass, ec) catch {
                kprint("esp exception class not found \n", .{});
                return;
            };

            kprint(".........sync int............\n", .{});
            kprint("Exception Class(from esp reg): {s} \n", .{@tagName(ec_en)});
            kprint("Int Type: {s} \n", .{@tagName(int_type)});

            if (il == 1) {
                kprint("32 bit instruction trapped \n", .{});
            } else {
                kprint("16 bit instruction trapped \n", .{});
            }
            kprint(".........sync int............\n", .{});
        },
        iC.ExceptionType.el1Irq, iC.ExceptionType.el1Fiq => {
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
                            kprint("Unknown({s}) bank 1 irq num: {s} \n", .{ @tagName(int_type), @tagName(irq_bank_1) });
                        },
                    }
                },
                // One or more bits set in pending register 2
                Bank0.pending2 => {
                    switch (irq_bank_2) {
                        else => {
                            kprint("Unknown({s}) bank 2 irq num: {s} \n", .{ @tagName(int_type), @tagName(irq_bank_2) });
                        },
                    }
                },
                else => {
                    kprint("Unknown({s}) bank 0 irq num: {s} \n", .{ @tagName(int_type), @tagName(irq_bank_0) });
                },
            }
        },
        else => {
            kprint("unhandled int type! \n", .{});
        },
    }
}
pub fn irqElxSpx() callconv(.C) void {}
