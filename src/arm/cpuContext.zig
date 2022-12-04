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
        asm volatile ("mov x8, %[context_addr]"
            :
            : [context_addr] "rax" (@ptrToInt(context)),
        );

        asm volatile ("ldp x0, x1, [x8], #16");
        asm volatile ("ldp x2, x3, [x8], #16");
        asm volatile ("ldp x4, x5, [x8], #16");
        asm volatile ("ldp x6, x7, [x8], #16");
        // todo => restore x8 as well
        asm volatile ("ldp xzr, x9, [x8], #16");
        asm volatile ("ldp x10, x11, [x8], #16");
        asm volatile ("ldp x12, x13, [x8], #16");
        asm volatile ("ldp x14, x15, [x8], #16");
        asm volatile ("ldp x16, x17, [x8], #16");
        asm volatile ("ldp x18, x19, [x8], #16");
        asm volatile ("ldp x20, x21, [x8], #16");
        asm volatile ("ldp x22, x23, [x8], #16");
        asm volatile ("ldp x24, x25, [x8], #16");
        asm volatile ("ldp x26, x27, [x8], #16");
        asm volatile ("ldp x28, x29, [x8], #16");

        // x30, sp
        asm volatile ("ldp x30, x0, [x8], #16");
        asm volatile ("mov sp, x0");

        // elr_el1, fp
        asm volatile ("ldp x0, x1, [x8], #16");
        asm volatile ("mov fp, x0");
        asm volatile ("msr elr_el1, x1");
    }

    pub export fn restoreContextFromStack() callconv(.C) void {
        asm volatile ("ldp x0, x1, [sp, #16 * 16]");
        asm volatile ("msr elr_el1, x0");
        asm volatile ("mov fp, x1");

        asm volatile ("ldp x0, x30, [sp, #16 * 15]");
        asm volatile ("mov sp, x0");

        asm volatile ("ldp x28, x29, [sp, #16 * 14]");
        asm volatile ("ldp x26, x27, [sp, #16 * 13]");
        asm volatile ("ldp x24, x25, [sp, #16 * 12]");
        asm volatile ("ldp x22, x23, [sp, #16 * 11]");
        asm volatile ("ldp x20, x21, [sp, #16 * 10]");
        asm volatile ("ldp x18, x19, [sp, #16 * 9]");
        asm volatile ("ldp x16, x17, [sp, #16 * 8]");
        asm volatile ("ldp x14, x15, [sp, #16 * 7]");
        asm volatile ("ldp x12, x13, [sp, #16 * 6]");
        asm volatile ("ldp x10, x11, [sp, #16 * 5]");
        asm volatile ("ldp x8, x9, [sp, #16 * 4]");
        asm volatile ("ldp x6, x7, [sp, #16 * 3]");
        asm volatile ("ldp x4, x5, [sp, #16 * 2]");
        asm volatile ("ldp x2, x3, [sp, #16 * 1]");
        asm volatile ("ldp x0, x1, [sp, #16 * 0]");

        asm volatile ("add sp, sp, %[context_size]"
            :
            : [context_size] "rax" (@sizeOf(CpuContext)),
        );
    }

    export fn saveCurrContextOnStack(int_type: usize) callconv(.Naked) void {
        // todo => NAKED doesn't work 2 is static, fix!!
        _ = int_type;
        asm volatile ("sub sp, sp, %[context_size]"
            :
            : [context_size] "rax" (@sizeOf(CpuContext)),
        );

        asm volatile ("stp x0, x1, [sp, #16 * 0]");
        asm volatile ("stp x2, x3, [sp, #16 * 1]");
        asm volatile ("stp x4, x5, [sp, #16 * 2]");
        asm volatile ("stp x6, x7, [sp, #16 * 3]");
        asm volatile ("stp x8, x9, [sp, #16 * 4]");
        asm volatile ("stp x10, x11, [sp, #16 * 5]");
        asm volatile ("stp x12, x13, [sp, #16 * 6]");
        asm volatile ("stp x14, x15, [sp, #16 * 7]");
        asm volatile ("stp x16, x17, [sp, #16 * 8]");
        asm volatile ("stp x18, x19, [sp, #16 * 9]");
        asm volatile ("stp x20, x21, [sp, #16 * 10]");
        asm volatile ("stp x22, x23, [sp, #16 * 11]");
        asm volatile ("stp x24, x25, [sp, #16 * 12]");
        asm volatile ("stp x26, x27, [sp, #16 * 13]");
        asm volatile ("stp x28, x29, [sp, #16 * 14]");
        asm volatile ("mov x0, sp");
        asm volatile ("stp x30, x0, [sp, #16 * 15]");
        asm volatile ("mov x0, fp");
        asm volatile ("mrs x1, elr_el1");
        asm volatile ("stp x0, x1, [sp, #16 * 16]");

        asm volatile ("mrs x0, far_el1");
        asm volatile ("mrs x1, esr_el1");
        asm volatile ("stp x0, x1, [sp, #16 * 17]");

        asm volatile ("mrs x0, CurrentEL");
        asm volatile ("lsr x0, x0, #2");
        // kprint("INT TYPE: {d} \n", .{int_type});
        asm volatile ("stp x0, %[int_type], [sp, #16 * 18]"
            :
            : [int_type] "rax" (2),
        );
    }
};
