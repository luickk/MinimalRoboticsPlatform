const std = @import("std");
const bl_utils = @import("utils.zig");
const arm = @import("arm");
const ProccessorRegMap = arm.processor.ProccessorRegMap;
const CpuContext = arm.cpuContext.CpuContext;
const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr0).kprint;
const gic = arm.gicv2;
const timer = arm.timer;

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

pub fn irqHandler(temp_context: *CpuContext, tmp_int_type: usize) callconv(.C) void {
    var int_type = tmp_int_type;
    var int_type_en = std.meta.intToEnum(gic.ExceptionType, int_type) catch return;
    temp_context.int_type = int_type;
    kprint("bl irqHandler \n", .{});

    if (int_type_en == gic.ExceptionType.el1Sync) {
        var iss = @truncate(u25, temp_context.esr_el1);
        var ifsc = @truncate(u6, temp_context.esr_el1);
        var il = @truncate(u1, temp_context.esr_el1 >> 25);
        var ec = @truncate(u6, temp_context.esr_el1 >> 26);
        var iss2 = @truncate(u5, temp_context.esr_el1 >> 32);
        _ = iss;
        _ = iss2;

        var ec_en = std.meta.intToEnum(ExceptionClass, ec) catch {
            kprint("esp exception class not found \n", .{});
            bl_utils.panic();
        };
        var ifsc_en = std.meta.intToEnum(ProccessorRegMap.Esr_el1.Ifsc, ifsc) catch {
            kprint("esp exception class not found \n", .{});
            return;
        };

        kprint(".........sync exc............\n", .{});
        kprint("Exception Class(from esp reg): {s} \n", .{@tagName(ec_en)});
        kprint("IFC(from esp reg): {s} \n", .{@tagName(ifsc_en)});
        kprint("- debug info: \n", .{});
        kprint("Int Type: {s} \n", .{@tagName(int_type_en)});
        kprint("el: {d} \n", .{temp_context.el});
        kprint("esr_el1: 0x{x} \n", .{temp_context.esr_el1});
        kprint("far_el1: 0x{x} \n", .{temp_context.far_el1});
        kprint("elr_el1: 0x{x} \n", .{temp_context.elr_el1});
        kprint("- sys regs: \n", .{});
        kprint("sp: 0x{x} \n", .{temp_context.sp});
        kprint("sp_el0: 0x{x} \n", .{temp_context.sp_el0});
        kprint("spSel: {d} \n", .{temp_context.sp_sel});
        kprint("lr(x30): 0x{x} \n", .{temp_context.x30});
        kprint("x0: 0x{x}, x1: 0x{x}, x2: 0x{x}, x3: 0x{x}, x4: 0x{x} \n", .{ temp_context.x0, temp_context.x1, temp_context.x2, temp_context.x3, temp_context.x4 });
        kprint("x5: 0x{x}, x6: 0x{x}, x7: 0x{x}, x8: 0x{x}, x9: 0x{x} \n", .{ temp_context.x5, temp_context.x6, temp_context.x7, temp_context.x8, temp_context.x9 });
        kprint("x10: 0x{x}, x11: 0x{x}, x12: 0x{x}, x13: 0x{x}, x14: 0x{x} \n", .{ temp_context.x10, temp_context.x11, temp_context.x12, temp_context.x13, temp_context.x14 });
        kprint("x15: 0x{x}, x16: 0x{x}, x17: 0x{x}, x18: 0x{x}, x19: 0x{x} \n", .{ temp_context.x15, temp_context.x16, temp_context.x17, temp_context.x18, temp_context.x19 });
        kprint("x20: 0x{x}, x21: 0x{x}, x22: 0x{x}, x23: 0x{x}, x24: 0x{x} \n", .{ temp_context.x20, temp_context.x21, temp_context.x22, temp_context.x23, temp_context.x24 });
        kprint("x25: 0x{x}, x26: 0x{x}, x27: 0x{x}, x28: 0x{x}, x29: 0x{x} \n", .{ temp_context.x25, temp_context.x26, temp_context.x27, temp_context.x28, temp_context.x29 });

        if (il == 1) {
            kprint("32 bit instruction trapped \n", .{});
        } else {
            kprint("16 bit instruction trapped \n", .{});
        }
        kprint(".........sync temp_context............\n", .{});
    }
    bl_utils.panic();
}
pub fn irqElxSpx() callconv(.C) void {
    kprint("irqElxSpx \n", .{});
}
