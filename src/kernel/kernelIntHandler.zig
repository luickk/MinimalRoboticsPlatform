const std = @import("std");
const arm = @import("arm");
const CpuContext = arm.cpuContext.CpuContext;
const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr1).kprint;
const board = @import("board");
const bcm2835IntHandle = @import("board/raspi3b/bcm2835IntHandle.zig");
const gic = arm.gicv2;
const gt = arm.genericTimer;

pub const Esr_el1 = struct {
    pub const Ifsc = enum(u6) {
        addrSizeFaultLvl0 = 0b000000, // Address size fault, level 0 of translation or translation table base register.
        addrSizeFaultLvl1 = 0b000001, // Address size fault, level 1.
        addrSizeFaultLvl2 = 0b000010, // Address size fault, level 2.
        addrSizeFaultLvl3 = 0b000011, // Address size fault, level 3.
        transFaultLvl0 = 0b000100, // Translation fault, level 0.
        transFaultLvl1 = 0b000101, // Translation fault, level 1.
        transFaultLvl2 = 0b000110, // Translation fault, level 2.
        transFaultLvl3 = 0b000111, // Translation fault, level 3.
        accessFlagFaultLvl1 = 0b001001, // Access flag fault, level 1.
        accessFlagFaultLvl2 = 0b001010,
        accessFlagFaultLvl3 = 0b001011,
        accessFlagFaultLvl0 = 0b001000,
        permFaultLvl0 = 0b001100,
        permFaultLvl1 = 0b001101,
        permFaultLvl2 = 0b001110,
        permFaultLvl3 = 0b001111,
        syncExternalAbortNotOnTableWalk = 0b010000,
        syncExternalAbortNotOnTableWalkLvlN1 = 0b010011, // Synchronous External abort on translation table walk or hardware update of translation table, level -1.
        syncExternalAbortOnTableWalkLvl0 = 0b010100, // Synchronous External abort on translation table walk or hardware update of translation table, level 0.
        syncExternalAbortOnTableWalkLvl1 = 0b010101, // Synchronous External abort on translation table walk or hardware update of translation table, level 1.
        syncExternalAbortOnTableWalkLvl2 = 0b010110, // Synchronous External abort on translation table walk or hardware update of translation table, level 2.
        syncExternalAbortOnTableWalkLvl3 = 0b010111, // Synchronous External abort on translation table walk or hardware update of translation table, level 3.
        syncParityOrEccErrOnMemAccessOrWalk = 0b011000, // Synchronous parity or ECC error on memory access, not on translation table walk.
        syncParityOrEccErrOnMemAccessOrWalkLvlN1 = 0b011011, // Synchronous parity or ECC error on memory access on translation table walk or hardware update of translation table, level -1.
        syncParityOrEccErrOnMemAccessOrWalkLvl0 = 0b011100, // Synchronous parity or ECC error on memory access on translation table walk or hardware update of translation table, level 0.
        syncParityOrEccErrOnMemAccessOrWalkLvl1 = 0b011101, // Synchronous parity or ECC error on memory access on translation table walk or hardware update of translation table, level 1.
        syncParityOrEccErrOnMemAccessOrWalkLvl2 = 0b011110, // Synchronous parity or ECC error on memory access on translation table walk or hardware update of translation table, level 2.
        syncParityOrEccErrOnMemAccessOrWalkLvl3 = 0b011111, // Synchronous parity or ECC error on memory access on translation table walk or hardware update of translation table, level 3.
        granuleProtectionFaultOnWalkLvlN1 = 0b100011, // Granule Protection Fault on translation table walk or hardware update of translation table, level -1.
        granuleProtectionFaultOnWalkLvl0 = 0b100100, // Granule Protection Fault on translation table walk or hardware update of translation table, level 0.
        granuleProtectionFaultOnWalkLvl1 = 0b100101, // Granule Protection Fault on translation table walk or hardware update of translation table, level 1.
        granuleProtectionFaultOnWalkLvl2 = 0b100110, // Granule Protection Fault on translation table walk or hardware update of translation table, level 2.
        granuleProtectionFaultOnWalkLvl3 = 0b100111, // Granule Protection Fault on translation table walk or hardware update of translation table, level 3.
        granuleProtectionFaultNotOnWalk = 0b101000, // Granule Protection Fault, not on translation table walk or hardware update of translation table.
        addrSizeFaukltLvlN1 = 0b101001, // Address size fault, level -1.
        transFaultLvlN1 = 0b101011, // Translation fault, level -1.
        tlbConflictAbort = 0b110000, // TLB conflict abort.
        unsupportedAtomicHardwareUpdateFault = 0b110001, // Unsupported atomic hardware update fault.
    };

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
};

pub fn irqHandler(temp_context: *CpuContext) callconv(.C) void {
    // copy away from stack top
    var context = temp_context.*;

    // std intToEnum instead of build in in order to catch err
    var int_type = std.meta.intToEnum(gic.ExceptionType, context.int_type) catch gic.ExceptionType.unknown;

    switch (int_type) {
        gic.ExceptionType.el1Sync, gic.ExceptionType.elxSpx, gic.ExceptionType.unknown => {
            var iss = @truncate(u25, context.esr_el1);
            var ifsc = @truncate(u6, context.esr_el1);
            var il = @truncate(u1, context.esr_el1 >> 25);
            var ec = @truncate(u6, context.esr_el1 >> 26);
            var iss2 = @truncate(u5, context.esr_el1 >> 32);
            _ = iss;
            _ = iss2;

            var ec_en = std.meta.intToEnum(Esr_el1.ExceptionClass, ec) catch {
                kprint("esp exception class not found \n", .{});
                return;
            };
            var ifsc_en = std.meta.intToEnum(Esr_el1.Ifsc, ifsc) catch {
                kprint("esp exception class not found \n", .{});
                return;
            };

            kprint(".........sync exc............\n", .{});
            kprint("Exception Class(from esp reg): {s} \n", .{@tagName(ec_en)});
            kprint("IFC(from esp reg): {s} \n", .{@tagName(ifsc_en)});
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
            kprint("x0: 0x{x}, x1: 0x{x}, x2: 0x{x}, x3: 0x{x}, x4: 0x{x} \n", .{ context.x0, context.x1, context.x2, context.x3, context.x4 });
            kprint("x5: 0x{x}, x6: 0x{x}, x7: 0x{x}, x8: 0x{x}, x9: 0x{x} \n", .{ context.x5, context.x6, context.x7, context.x8, context.x9 });
            kprint("x10: 0x{x}, x11: 0x{x}, x12: 0x{x}, x13: 0x{x}, x14: 0x{x} \n", .{ context.x10, context.x11, context.x12, context.x13, context.x14 });
            kprint("x15: 0x{x}, x16: 0x{x}, x17: 0x{x}, x18: 0x{x}, x19: 0x{x} \n", .{ context.x15, context.x16, context.x17, context.x18, context.x19 });
            kprint("x20: 0x{x}, x21: 0x{x}, x22: 0x{x}, x23: 0x{x}, x24: 0x{x} \n", .{ context.x20, context.x21, context.x22, context.x23, context.x24 });
            kprint("x25: 0x{x}, x26: 0x{x}, x27: 0x{x}, x28: 0x{x}, x29: 0x{x} \n", .{ context.x25, context.x26, context.x27, context.x28, context.x29 });

            if (il == 1) {
                kprint("32 bit instruction trapped \n", .{});
            } else {
                kprint("16 bit instruction trapped \n", .{});
            }
            kprint(".........sync exc............\n", .{});
            if (ec_en == Esr_el1.ExceptionClass.bkptInstExecAarch64) {
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
pub fn irqElxSpx(temp_context: *CpuContext) callconv(.C) void {
    kprint("!elx/ spx interrupt fired! \n", .{});
    irqHandler(temp_context);
}
