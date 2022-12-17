const std = @import("std");
const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr1).kprint;

// todo => add  SIMD/FP and thread ids...
pub const CpuContext = packed struct {
    // debug info
    int_type: usize,
    el: usize,
    far_el1: usize,
    esr_el1: usize,
    sp_sel: usize,
    pc: usize,

    // sys regs
    elr_el1: usize,
    fp: usize,
    sp: usize,

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
    d31: usize,
    d30: usize,
    d29: usize,
    d28: usize,
    d27: usize,
    d26: usize,
    d25: usize,
    d24: usize,
    d23: usize,
    d22: usize,
    d21: usize,
    d20: usize,
    d19: usize,
    d18: usize,
    d17: usize,
    d16: usize,
    d15: usize,
    d14: usize,
    d13: usize,
    d12: usize,
    d11: usize,
    d10: usize,
    d9: usize,
    d8: usize,
    d7: usize,
    d6: usize,
    d5: usize,
    d4: usize,
    d3: usize,
    d2: usize,
    d1: usize,
    d0: usize,

    pub fn init() CpuContext {
        return std.mem.zeroInit(CpuContext, .{});
    }

    // note: x8, x0, x1 are not fully restored!
    pub export fn restoreContextFromMem(context: *CpuContext) callconv(.C) void {
        const context_addr: u64 = @ptrToInt(context);
        asm volatile (
        // base addr
            \\mov x8, %[context_addr]
            // debug regs
            \\ldp x0, x1, [x8], #16
            \\ldp x0, x1, [x8], #16
            \\ldp x0, x1, [x8], #16
            // system regs
            \\ldp x1, x0, [x8], #16
            \\msr elr_el1, x1
            \\mov fp, x0
            \\ldp x0, x30, [x8], #16
            \\mov sp, x0
            // gp regs
            \\ldp x29, x28, [x8], #16
            \\ldp x27, x26, [x8], #16
            \\ldp x25, x24, [x8], #16
            \\ldp x23, x22, [x8], #16
            \\ldp x21, x20, [x8], #16
            \\ldp x19, x18,[x8], #16
            \\ldp x17, x16, [x8], #16
            \\ldp x15, x14, [x8], #16
            \\ldp x13, x12, [x8], #16
            \\ldp x11, x10, [x8], #16
            \\ldp x9, xzr, [x8], #16
            \\ldp x7, x6, [x8], #16
            \\ldp x5, x4, [x8], #16
            \\ldp x3, x2, [x8], #16
            \\ldp x1, x0, [x8], #16
            // smid regs
            \\ldp d31, d30, [x8], #16
            \\ldp d29, d28, [x8], #16
            \\ldp d27, d26, [x8], #16
            \\ldp d25, d24, [x8], #16
            \\ldp d23, d22, [x8], #16
            \\ldp d21, d20, [x8], #16
            \\ldp d19, d18, [x8], #16
            \\ldp d17, d16, [x8], #16
            \\ldp d15, d14, [x8], #16
            \\ldp d13, d12, [x8], #16
            \\ldp d11, d10, [x8], #16
            \\ldp d9, d8, [x8], #16
            \\ldp d7, d6, [x8], #16
            \\ldp d5, d4, [x8], #16
            \\ldp d3, d2, [x8], #16
            \\ldp d1, d0, [x8], #16
            \\add sp, sp, %[cpu_context_size]
            :
            : [context_addr] "r" (context_addr),
              [cpu_context_size] "I" (@sizeOf(CpuContext)),
            : "x*"
        );
    }

    // labels are not functions in cpuContext.zig since fns would manipulate the sp which needs to stay the same
    // since the CpuState is pushed there
    comptime {
        // label restoreContextFromStack args: none
        // x1 is not restored since it's used as clobbers
        asm (
            \\.globl  _restoreContextFromStack
            \\_restoreContextFromStack:
            // pop and discard debug info
            \\ldp x0, x1, [sp], #16
            \\ldp x0, x1, [sp], #16
            \\ldp x0, x1, [sp], #16
            // sys regs
            \\ldp x0, x1, [sp], #16
            \\msr elr_el1, x0
            \\mov fp, x1
            \\ldp x0, x30, [sp], #16
            \\mov sp, x0
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
            \\ldp d31, d30, [sp], #16
            \\ldp d29, d28, [sp], #16
            \\ldp d27, d26, [sp], #16
            \\ldp d25, d24, [sp], #16
            \\ldp d23, d22, [sp], #16
            \\ldp d21, d20, [sp], #16
            \\ldp d19, d18, [sp], #16
            \\ldp d17, d16, [sp], #16
            \\ldp d15, d14, [sp], #16
            \\ldp d13, d12, [sp], #16
            \\ldp d11, d10, [sp], #16
            \\ldp d9, d8, [sp], #16
            \\ldp d7, d6, [sp], #16
            \\ldp d5, d4, [sp], #16
            \\ldp d3, d2, [sp], #16
            \\ldp d1, d0, [sp], #16
            // \\add sp, sp, #{d}
            \\eret
        );

        // label sadeCurrContextOnStack args: x2: int_type
        // x2 is not saded bc it's used as arg (x0,x1 are clobbers but after push to stack)
        asm (
            \\.globl _saveCurrContextOnStack
            \\_saveCurrContextOnStack:
            // \\sub sp, sp, #{d}
            \\stp d1, d0, [sp, #-16]!
            \\stp d3, d2, [sp, #-16]!
            \\stp d5, d4, [sp, #-16]!
            \\stp d7, d6, [sp, #-16]!
            \\stp d9, d8, [sp, #-16]!
            \\stp d11, d10, [sp, #-16]!
            \\stp d13, d12, [sp, #-16]!
            \\stp d15, d14, [sp, #-16]!
            \\stp d17, d16, [sp, #-16]!
            \\stp d19, d18, [sp, #-16]!
            \\stp d21, d20, [sp, #-16]!
            \\stp d23, d22, [sp, #-16]!
            \\stp d25, d24, [sp, #-16]!
            \\stp d27, d26, [sp, #-16]!
            \\stp d29, d28, [sp, #-16]!
            \\stp d31, d30, [sp, #-16]!
            // gp regs
            \\stp x1, x0, [sp, #-16]!
            \\stp x3, x2, [sp, #-16]!
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
            \\mov x0, sp
            \\stp x0, x30, [sp, #-16]!
            \\mov x0, fp
            \\mrs x1, elr_el1
            \\stp x1, x0, [sp, #-16]!

            // debug regs
            \\adr x0, .
            \\mrs x1, SPSel
            \\stp x1, x0, [sp, #-16]!
            \\mrs x0, far_el1
            \\mrs x1, esr_el1
            \\stp x0, x1, [sp, #-16]!
            \\mrs x0, CurrentEL
            \\lsr x0, x0, #2
            \\stp x2, x0, [sp, #-16]!
            \\ret
        );
    }
};
