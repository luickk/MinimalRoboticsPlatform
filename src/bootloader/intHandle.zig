const std = @import("std");
const periph = @import("peripherals");
const kprint = periph.serial.kprint;
const addr = periph.rbAddr.InterruptController;
const iC = periph.intController;
const timer = periph.timer;

const Bank0 = addr.Values.Bank0;
const Bank1 = addr.Values.Bank1;
const Bank2 = addr.Values.Bank2;

pub fn irqHandler(exc: *iC.ExceptionFrame) callconv(.C) void {

    // std intToEnum instead of build in in order to catch err
    var int_type = std.meta.intToEnum(iC.ExceptionType, exc.int_type) catch {
        kprint("int type not found \n", .{});
        return;
    };
    if (int_type == iC.ExceptionType.el1Sync) {
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

        kprint(".........sync exc............\n", .{});
        kprint("Exception Class(from esp reg): {s} \n", .{@tagName(ec_en)});
        kprint("Int Type: {s} \n", .{@tagName(int_type)});

        if (il == 1) {
            kprint("32 bit instruction trapped \n", .{});
        } else {
            kprint("16 bit instruction trapped \n", .{});
        }
        kprint(".........sync exc............\n", .{});
    }
    var irq_bank_0 = std.meta.intToEnum(Bank0, @intToPtr(*u32, addr.pendingBasic).*) catch {
        kprint("bank0 int type not found. \n", .{});
        return;
    };
    var irq_bank_1 = std.meta.intToEnum(Bank1, @intToPtr(*u32, addr.pendingIrq1).*) catch {
        kprint("bank1 int type not found. \n", .{});
        return;
    };
    var irq_bank_2 = std.meta.intToEnum(Bank2, @intToPtr(*u32, addr.pendingIrq2).*) catch {
        kprint("bank2 int type not found. \n", .{});
        return;
    };
    kprint(".........Async int............\n", .{});
    kprint("Async ({s}) bank irq num: {s} \n", .{ @tagName(int_type), @tagName(irq_bank_0) });
    kprint("Bank 0: {s}; Bank 1: {s}; Bank 2: {s} \n", .{ @tagName(irq_bank_0), @tagName(irq_bank_1), @tagName(irq_bank_2) });
    kprint(".........Async int............\n", .{});
}
pub fn irqElxSpx() callconv(.C) void {}
