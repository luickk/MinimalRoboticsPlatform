const kprint = @import("serial.zig").kprint;
const addr = @import("raspberryAddr.zig").iC;

// identifiers for the vector table addr_handler call
pub export const EL1_SYNC: u64 = 0x1;
pub export const EL1_IRQ: u64 = 0x2;
pub export const EL1_FIQ: u64 = 0x3;
pub export const EL1_ERR: u64 = 0x4;
pub export const ELX_SPX: u64 = 0x5;

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

// reads interrupt data placed by exc. vec from the stack
pub const ExceptionFrame = struct {
    regs: [30]u64,
    int_type: u64,
    esr_el1: u64,
    lr: u64,
};

pub fn timerInit() void {
    var cur_val: u32 = @intToPtr(*u32, addr.timerClo).*;
    cur_val += addr.timerInterval;
    @intToPtr(*u32, addr.timerC1).* = cur_val;
}

pub fn initIc() void {
    // enabling all irq types
    @intToPtr(*u32, addr.enableIrq1).* = 1;
    @intToPtr(*u32, addr.enableIrq2).* = 1;
    @intToPtr(*u32, addr.enableIrqBasic).* = 1;

    // configure irq mask
    asm volatile ("msr daifclr, #0");
}
