const std = @import("std");
const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr1).kprint;

pub const CpuContext = packed struct {
    // debug info
    int_type: usize,
    el: usize,
    far_el1: usize,
    esr_el1: usize,
    sp_sel: usize,

    // sys regs
    sp_el0: usize,
    elr_el1: usize,
    fp: usize,
    sp_el1: usize,

    // gp regs
    x30: usize,
    x29: usize,
    x28: usize,
    x27: usize,
    x26: usize,
    x25: usize,
    x24: usize,
    x23: usize,
    x22: usize,
    x21: usize,
    x20: usize,
    x19: usize,
    x18: usize,
    x17: usize,
    x16: usize,
    x15: usize,
    x14: usize,
    x13: usize,
    x12: usize,
    x11: usize,
    x10: usize,
    x9: usize,
    x8: usize,
    x7: usize,
    x6: usize,
    x5: usize,
    x4: usize,
    x3: usize,
    x2: usize,
    x1: usize,
    x0: usize,

    // smid regs
    q31: f128,
    q30: f128,
    q29: f128,
    q28: f128,
    q27: f128,
    q26: f128,
    q25: f128,
    q24: f128,
    q23: f128,
    q22: f128,
    q21: f128,
    q20: f128,
    q19: f128,
    q18: f128,
    q17: f128,
    q16: f128,
    q15: f128,
    q14: f128,
    q13: f128,
    q12: f128,
    q11: f128,
    q10: f128,
    q9: f128,
    q8: f128,
    q7: f128,
    q6: f128,
    q5: f128,
    q4: f128,
    q3: f128,
    q2: f128,
    q1: f128,
    q0: f128,

    pub fn init() CpuContext {
        return std.mem.zeroInit(CpuContext, .{});
    }

    // the labels are not functions since fns would manipulate the sp which needs to stay the same
    // since the CpuState is pushed there
    // _restoreContextFromSp restores sp to sp_el0 if SpSel is sp_el1 and the otherway around
    // that way all registers can be restored without clobbers. Requires that SpSel is set to a different one then
    // currently selected.
    comptime {
        asm (
            \\.globl _restoreContextFromSp
            \\_restoreContextFromSp:
            // pop and discard debug info
            \\ldp x0, x1, [sp], #16
            \\ldp x0, x1, [sp], #16
            \\ldp x0, x2, [sp], #16
            // sys regs
            \\ldp x0, x1, [sp], #16
            \\msr elr_el1, x0
            \\mov fp, x1
            \\ldp x1, x30, [sp], #16

            // * loading context struct sp to correct el sp *
            \\mrs x0, spsel
            // spsel == 0
            \\cmp x0, #0
            \\beq load_sp_to_el1
            // spsel == 1
            \\msr sp_el0, x2
            \\b skip_sp_to_el1_load
            // spsel == 0
            \\load_sp_to_el1:
            \\msr spsel, #1
            // \\add x1, x1, #752
            \\mov sp, x1
            \\msr spsel, #0
            \\skip_sp_to_el1_load:
            // * *

            // gp regs
            \\ldp x29, x28, [sp], #16
            \\ldp x27, x26, [sp], #16
            \\ldp x25, x24, [sp], #16
            \\ldp x23, x22, [sp], #16
            \\ldp x21, x20, [sp], #16
            \\ldp x19, x18, [sp], #16
            \\ldp x17, x16, [sp], #16
            \\ldp x15, x14, [sp], #16
            \\ldp x13, x12, [sp], #16
            \\ldp x11, x10, [sp], #16
            \\ldp x9, x8, [sp], #16
            \\ldp x7, x6, [sp], #16
            \\ldp x5, x4, [sp], #16
            \\ldp x3, x2, [sp], #16
            \\ldp x1, x0, [sp], #16
            // smid regs
            \\ldp q31, q30, [sp], #32
            \\ldp q29, q28, [sp], #32
            \\ldp q27, q26, [sp], #32
            \\ldp q25, q24, [sp], #32
            \\ldp q23, q22, [sp], #32
            \\ldp q21, q20, [sp], #32
            \\ldp q19, q18, [sp], #32
            \\ldp q17, q16, [sp], #32
            \\ldp q15, q14, [sp], #32
            \\ldp q13, q12, [sp], #32
            \\ldp q11, q10, [sp], #32
            \\ldp q9, q8, [sp], #32
            \\ldp q7, q6, [sp], #32
            \\ldp q5, q4, [sp], #32
            \\ldp q3, q2, [sp], #32
            \\ldp q1, q0, [sp], #32
            \\eret
        );
        asm (
            \\.globl _restoreContextWithoutSwitchFromSp
            \\_restoreContextWithoutSwitchFromSp:
            // pop and discard debug info
            \\ldp x0, x1, [sp], #16
            \\ldp x0, x1, [sp], #16
            \\ldp x0, x1, [sp], #16
            // sys regs
            \\msr sp_el0, x1
            \\ldp x0, x1, [sp], #16
            \\msr elr_el1, x0
            \\mov fp, x1
            \\ldp x1, x30, [sp], #16
            // \\mov sp, x1
            // gp regs
            \\ldp x29, x28, [sp], #16
            \\ldp x27, x26, [sp], #16
            \\ldp x25, x24, [sp], #16
            \\ldp x23, x22, [sp], #16
            \\ldp x21, x20, [sp], #16
            \\ldp x19, x18, [sp], #16
            \\ldp x17, x16, [sp], #16
            \\ldp x15, x14, [sp], #16
            \\ldp x13, x12, [sp], #16
            \\ldp x11, x10, [sp], #16
            \\ldp x9, x8, [sp], #16
            \\ldp x7, x6, [sp], #16
            \\ldp x5, x4, [sp], #16
            \\ldp x3, x2, [sp], #16
            \\ldp x1, x0, [sp], #16
            // smid regs
            \\ldp q31, q30, [sp], #32
            \\ldp q29, q28, [sp], #32
            \\ldp q27, q26, [sp], #32
            \\ldp q25, q24, [sp], #32
            \\ldp q23, q22, [sp], #32
            \\ldp q21, q20, [sp], #32
            \\ldp q19, q18, [sp], #32
            \\ldp q17, q16, [sp], #32
            \\ldp q15, q14, [sp], #32
            \\ldp q13, q12, [sp], #32
            \\ldp q11, q10, [sp], #32
            \\ldp q9, q8, [sp], #32
            \\ldp q7, q6, [sp], #32
            \\ldp q5, q4, [sp], #32
            \\ldp q3, q2, [sp], #32
            \\ldp q1, q0, [sp], #32
            \\eret
        );
        // _saveCurrContextOnStack is now embedded in bl&kernel exc_vector.S
        // todo => move it back here (without trashing x30...)
        asm (
            \\.globl _saveCurrContextOnStack
            \\_saveCurrContextOnStack:
            \\stp q1, q0, [sp, #-32]!
            \\stp q3, q2, [sp, #-32]!
            \\stp q5, q4, [sp, #-32]!
            \\stp q7, q6, [sp, #-32]!
            \\stp q9, q8, [sp, #-32]!
            \\stp q11, q10, [sp, #-32]!
            \\stp q13, q12, [sp, #-32]!
            \\stp q15, q14, [sp, #-32]!
            \\stp q17, q16, [sp, #-32]!
            \\stp q19, q18, [sp, #-32]!
            \\stp q21, q20, [sp, #-32]!
            \\stp q23, q22, [sp, #-32]!
            \\stp q25, q24, [sp, #-32]!
            \\stp q27, q26, [sp, #-32]!
            \\stp q29, q28, [sp, #-32]!
            \\stp q31, q30, [sp, #-32]!
            // gp regs
            \\stp x1, x0, [sp, #-16]!
            \\stp x3, x1, [sp, #-16]!
            \\stp x5, x4, [sp, #-16]!
            \\stp x7, x6, [sp, #-16]!
            \\stp x9, x8, [sp, #-16]!
            \\stp x11, x10, [sp, #-16]!
            \\stp x13, x12, [sp, #-16]!
            \\stp x15, x14, [sp, #-16]!
            \\stp x17, x16, [sp, #-16]!
            \\stp x19, x18, [sp, #-16]!
            \\stp x21, x20, [sp, #-16]!
            \\stp x23, x22, [sp, #-16]!
            \\stp x25, x24, [sp, #-16]!
            \\stp x27, x26, [sp, #-16]!
            \\stp x29, x28, [sp, #-16]!

            // sys regs
            \\mov x1, sp
            \\stp x1, x30, [sp, #-16]!
            \\mov x0, fp
            \\mrs x3, elr_el1
            \\stp x3, x0, [sp, #-16]!
            \\mrs x0, sp_el0

            // debug regs
            \\mrs x3, SPSel
            \\stp x3, x0, [sp, #-16]!
            \\mrs x0, far_el1
            \\mrs x3, esr_el1
            \\stp x0, x3, [sp, #-16]!
            \\mrs x0, CurrentEL
            \\lsr x0, x0, #2
            \\stp xzr, x0, [sp, #-16]!
            \\ret
        );
    }
};
