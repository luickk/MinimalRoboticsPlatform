const std = @import("std");
const arm = @import("arm");
const CpuContext = arm.cpuContext.CpuContext;
const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr1).kprint;
const board = @import("board");
const bcm2835IntHandle = @import("board/raspi3b/bcm2835IntHandle.zig");
const gic = arm.gicv2;
const gt = arm.genericTimer;

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

pub fn irqHandler(temp_context: *CpuContext) callconv(.C) void {
    // copy away from stack top
    var context = temp_context.*;

    // std intToEnum instead of build in in order to catch err
    var int_type = std.meta.intToEnum(gic.ExceptionType, context.int_type) catch {
        kprint("int type not found \n", .{});
        return;
    };
    switch (int_type) {
        gic.ExceptionType.el1Sync => {
            var iss = @truncate(u25, context.esr_el1);
            var il = @truncate(u1, context.esr_el1 >> 25);
            var ec = @truncate(u6, context.esr_el1 >> 26);
            var iss2 = @truncate(u5, context.esr_el1 >> 32);
            _ = iss;
            _ = iss2;

            var ec_en = std.meta.intToEnum(ExceptionClass, ec) catch {
                kprint("esp exception class not found \n", .{});
                return;
            };

            kprint(".........sync exc............\n", .{});
            kprint("Exception Class(from esp reg): {s} \n", .{@tagName(ec_en)});
            kprint("- debug info: \n", .{});
            kprint("Int Type: {s} \n", .{@tagName(int_type)});
            kprint("el: {d} \n", .{context.el});
            kprint("esr_el1: 0x{x} \n", .{context.esr_el1});
            kprint("far_el1: 0x{x} \n", .{context.far_el1});
            kprint("elr_el1: 0x{x} \n", .{context.elr_el1});
            kprint("- sys regs: \n", .{});
            kprint("sp: 0x{x} \n", .{context.sp});
            kprint("spSel: {d} \n", .{context.sp_sel});
            kprint("pc: 0x{x} \n", .{context.pc});
            kprint("lr(x30): 0x{x} \n", .{context.x30});
            kprint("x0: {x}, x1: {x}, x2: {x}, x3: {x}, x4: {x} \n", .{ context.x0, context.x1, context.x2, context.x3, context.x4 });
            kprint("x5: {x}, x6: {x}, x7: {x}, x8: {x}, x9: {x} \n", .{ context.x5, context.x6, context.x7, context.x8, context.x9 });
            kprint("x10: {x}, x11: {x}, x12: {x}, x13: {x}, x14: {x} \n", .{ context.x10, context.x11, context.x12, context.x13, context.x14 });
            kprint("x15: {x}, x16: {x}, x17: {x}, x18: {x}, x19: {x} \n", .{ context.x15, context.x16, context.x17, context.x18, context.x19 });
            kprint("x20: {x}, x21: {x}, x22: {x}, x23: {x}, x24: {x} \n", .{ context.x20, context.x21, context.x22, context.x23, context.x24 });
            kprint("x25: {x}, x26: {x}, x27: {x}, x28: {x}, x29: {x} \n", .{ context.x25, context.x26, context.x27, context.x28, context.x29 });

            if (il == 1) {
                kprint("32 bit instruction trapped \n", .{});
            } else {
                kprint("16 bit instruction trapped \n", .{});
            }
            kprint(".........sync exc............\n", .{});
            if (ec_en == ExceptionClass.bkptInstExecAarch64) {
                kprint("[kernel] halting execution due to debug trap\n", .{});
                while (true) {}
            }
        },
        gic.ExceptionType.el1Irq, gic.ExceptionType.el1Fiq => {
            if (board.config.board == .raspi3b)
                bcm2835IntHandle.irqHandler(&context);
            if (board.config.board == .qemuVirt)
                gt.timerInt(&context);
        },
        else => {
            kprint("{any} \n", .{context});
            kprint("unhandled int type! \n", .{});
        },
    }
}
pub fn irqElxSpx() callconv(.C) void {
    kprint("elx/ spx interrupt fired \n", .{});
}
