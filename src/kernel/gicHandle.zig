const std = @import("std");
const periph = @import("peripherals");
const kprint = periph.serial.kprint;
const board = @import("board");
const bcm2835IntHandle = @import("board/raspi3b/bcm2835IntHandle.zig");
const gic = periph.gicv2;
const timer = periph.timer;

pub fn irqHandler(exc: *gic.ExceptionFrame) callconv(.C) void {

    // std intToEnum instead of build in in order to catch err
    var int_type = std.meta.intToEnum(gic.ExceptionType, exc.int_type) catch {
        kprint("int type not found \n", .{});
        return;
    };
    switch (int_type) {
        gic.ExceptionType.el1Sync => {
            var iss = @truncate(u25, exc.esr_el1);
            var il = @truncate(u1, exc.esr_el1 >> 25);
            var ec = @truncate(u6, exc.esr_el1 >> 26);
            var iss2 = @truncate(u5, exc.esr_el1 >> 32);
            _ = iss;
            _ = iss2;

            var ec_en = std.meta.intToEnum(gic.ExceptionClass, ec) catch {
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
        gic.ExceptionType.el1Irq, gic.ExceptionType.el1Fiq => {
            if (board.Info.board == .raspi3b)
                bcm2835IntHandle.irqHandler(exc);
        },
        else => {
            kprint("unhandled int type! \n", .{});
        },
    }
}
pub fn irqElxSpx() callconv(.C) void {}
