const std = @import("std");
const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr1).kprint;

// todo => add  SIMD/FP and thread ids...
pub const CpuContext = packed struct {
    x0: usize,
    x1: usize,
    x2: usize,
    x3: usize,
    x4: usize,
    x5: usize,
    x6: usize,
    x7: usize,
    x8: usize,
    x9: usize,
    x10: usize,
    x11: usize,
    x12: usize,
    x13: usize,
    x14: usize,
    x15: usize,
    x16: usize,
    x17: usize,
    x18: usize,
    x19: usize,
    x20: usize,
    x21: usize,
    x22: usize,
    x23: usize,
    x24: usize,
    x25: usize,
    x26: usize,
    x27: usize,
    x28: usize,
    x29: usize,
    x30: usize,
    sp: usize,
    fp: usize,
    elr_el1: usize,

    // debug info
    esr_el1: usize,
    far_el1: usize,
    el: usize,
    int_type: usize,

    pub fn init() CpuContext {
        return std.mem.zeroInit(CpuContext, .{});
    }

    // note: x8, x0, x1 are not fully restored!
    pub export fn restoreContextFromMem(context: *CpuContext) callconv(.C) void {
        const context_addr: u64 = @ptrToInt(context);
        asm volatile (
            \\mov x8, %[context_addr]
            \\ldp x0, x1, [x8], #16
            \\ldp x2, x3, [x8], #16
            \\ldp x4, x5, [x8], #16
            \\ldp x6, x7, [x8], #16
            //todo => restore x8 as well
            \\ldp xzr, x9, [x8], #16
            \\ldp x10, x11, [x8], #16
            \\ldp x12, x13, [x8], #16
            \\ldp x14, x15, [x8], #16
            \\ldp x16, x17, [x8], #16
            \\ldp x18, x19, [x8], #16
            \\ldp x20, x21, [x8], #16
            \\ldp x22, x23, [x8], #16
            \\ldp x24, x25, [x8], #16
            \\ldp x26, x27, [x8], #16
            \\ldp x28, x29, [x8], #16
            // x30, sp
            \\ldp x30, x0, [x8], #16
            \\mov sp, x0
            // elr_el1, fp
            \\ldp x0, x1, [x8], #16
            \\mov fp, x0
            \\msr elr_el1, x1
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
        asm (std.fmt.comptimePrint(
                \\.globl  _restoreContextFromStack
                \\_restoreContextFromStack:
                \\ldp x0, x1, [sp, #16 * 16]
                \\msr elr_el1, x0
                \\mov fp, x1
                \\ldp x0, x30, [sp, #16 * 15]
                \\mov sp, x0
                \\ldp x28, x29, [sp, #16 * 14]
                \\ldp x26, x27, [sp, #16 * 13]
                \\ldp x24, x25, [sp, #16 * 12]
                \\ldp x22, x23, [sp, #16 * 11]
                \\ldp x20, x21, [sp, #16 * 10]
                \\ldp x18, x19, [sp, #16 * 9]
                \\ldp x16, x17, [sp, #16 * 8]
                \\ldp x14, x15, [sp, #16 * 7]
                \\ldp x12, x13, [sp, #16 * 6]
                \\ldp x10, x11, [sp, #16 * 5]
                \\ldp x8, x9, [sp, #16 * 4]
                \\ldp x6, x7, [sp, #16 * 3]
                \\ldp x4, x5, [sp, #16 * 2]
                \\ldp x2, x3, [sp, #16 * 1]
                \\ldp x0, x1, [sp, #16 * 0]
                \\ldr x1, #{d}
                \\sub sp, sp, x1
                \\ret
            , .{@sizeOf(CpuContext)}));

        // label saveCurrContextOnStack args: x2: int_type
        // x2 is not saved bc it's used as arg (x0,x1 are clobbers but after push to stack)
        asm (std.fmt.comptimePrint(
                \\.globl _saveCurrContextOnStack
                \\_saveCurrContextOnStack:
                \\sub sp, sp, #{d}
                \\stp x0, x1, [sp, #16 * 0]
                \\stp x2, x3, [sp, #16 * 1]
                \\stp x4, x5, [sp, #16 * 2]
                \\stp x6, x7, [sp, #16 * 3]
                \\stp x8, x9, [sp, #16 * 4]
                \\stp x10, x11, [sp, #16 * 5]
                \\stp x12, x13, [sp, #16 * 6]
                \\stp x14, x15, [sp, #16 * 7]
                \\stp x16, x17, [sp, #16 * 8]
                \\stp x18, x19, [sp, #16 * 9]
                \\stp x20, x21, [sp, #16 * 10]
                \\stp x22, x23, [sp, #16 * 11]
                \\stp x24, x25, [sp, #16 * 12]
                \\stp x26, x27, [sp, #16 * 13]
                \\stp x28, x29, [sp, #16 * 14]
                \\mov x0, sp
                \\stp x30, x0, [sp, #16 * 15]
                \\mov x0, fp
                \\mrs x1, elr_el1
                \\stp x0, x1, [sp, #16 * 16]
                \\mrs x0, far_el1
                \\mrs x1, esr_el1
                \\stp x0, x1, [sp, #16 * 17]
                \\mrs x0, CurrentEL
                \\lsr x0, x0, #2
                \\stp x0, x2, [sp, #16 * 18]
                \\ret
            , .{@sizeOf(CpuContext)}));
    }
};
