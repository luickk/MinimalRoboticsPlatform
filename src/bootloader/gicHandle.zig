const std = @import("std");
const bl_utils = @import("utils.zig");
const periph = @import("arm");
const bprint = periph.serial.bprint;
const gic = periph.gicv2;
const timer = periph.timer;

pub const ExceptionClass = enum(u6) {
    unknownReason = 0b000000,
    trappedWF = 0b000001,
    trappedMCR = 0b000011,
    trappedMcrr = 0b000100,
    trappedMCRWithAcc = 0b000101,
    trappedLdcStcAcc = 0b000110,
    sveAsmidFpAcc = 0b000111,
    trappedLdStInst = 0b001010,
    trappedMrrcWithAcc = 0b001100,
    branchTargetExc = 0b001101,
    illegalExecState = 0b001110,
    svcInstExcAArch32 = 0b010001,
    svcInstExAArch64 = 0b010101,
    trappedMsrMrsSiAarch64 = 0b011000,
    sveFuncTrappedAcc = 0b011001,
    excFromPointerAuthInst = 0b011100,
    instAbortFromLowerExcLvl = 0b100000,
    instAbortTakenWithoutExcLvlChange = 0b100001,
    pcAlignFaultExc = 0b100010,
    dataAbortFromLowerExcLvl = 0b100100,
    dataAbortWithoutExcLvlChange = 0b100101,
    spAlignmentFaultExc = 0b100110,
    trappedFpExcAarch32 = 0b101000,
    trappedFpExcAarch64 = 0b101100,
    brkPExcFromLowerExcLvl = 0b101111,
    brkPExcWithoutExcLvlChg = 0b110001,
    softwStepExcpFromLowerExcLvl = 0b110010,
    softwStepExcTakenWithoutExcLvlChange = 0b110011,
    watchPointExcpFromALowerExcLvl = 0b110100,
    watchPointExcpWithoutTakenWithoutExcLvlChange = 0b110101,
    bkptInstExecAarch32 = 0b111000,
    bkptInstExecAarch64 = 0b111100,
};

pub fn irqHandler(exc: *gic.ExceptionFrame) callconv(.C) void {
    bprint("irqHandler \n", .{});
    // std intToEnum instead of build in in order to catch err
    var int_type = std.meta.intToEnum(gic.ExceptionType, exc.int_type) catch {
        bprint("int type not found \n", .{});
        bl_utils.panic();
    };

    if (int_type == gic.ExceptionType.el1Sync) {
        var iss = @truncate(u25, exc.esr_el1);
        var il = @truncate(u1, exc.esr_el1 >> 25);
        var ec = @truncate(u6, exc.esr_el1 >> 26);
        var iss2 = @truncate(u5, exc.esr_el1 >> 32);
        _ = iss;
        _ = iss2;

        var ec_en = std.meta.intToEnum(ExceptionClass, ec) catch {
            bprint("esp exception class not found \n", .{});
            bl_utils.panic();
        };

        bprint(".........sync exc............\n", .{});
        bprint("Exception Class(from esp reg): {s} \n", .{@tagName(ec_en)});
        bprint("Int Type: {s} \n", .{@tagName(int_type)});

        if (il == 1) {
            bprint("32 bit instruction trapped \n", .{});
        } else {
            bprint("16 bit instruction trapped \n", .{});
        }
        bprint(".........sync exc............\n", .{});
    }
    bl_utils.panic();
}
pub fn irqElxSpx() callconv(.C) void {
    bprint("irqElxSpx \n", .{});
}
