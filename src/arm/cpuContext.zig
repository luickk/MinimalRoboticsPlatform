const std = @import("std");

pub const CpuContext = packed struct {

    // debug info
    int_type: usize,
    el: usize,
    far_el1: usize,
    esr_el1: usize,

    pc: usize,
    fp: usize,
    sp: usize,
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

    pub fn init() CpuContext {
        return std.mem.zeroInit(CpuContext, .{});
    }

    pub export fn restoreContextFromStruct(context: *CpuContext) callconv(.C) void {
        asm volatile ("mov x8, %[context_addr]"
            :
            : [context_addr] "rax" (@ptrToInt(context) + 32), // skipping frist 4 (4*8) CpuContext elements
        );

        // pc, fp
        asm volatile ("ldp x0, x1, [x8], #16");
        // sp, x30
        asm volatile ("ldp x0, x1, [x8], #16");

        asm volatile ("ldp x29, x28, [x8], #16");
        asm volatile ("ldp x27, x26, [x8], #16");
        asm volatile ("ldp x25, x24, [x8], #16");
        asm volatile ("ldp x23, x22, [x8], #16");
        asm volatile ("ldp x21, x20, [x8], #16");
        asm volatile ("ldp x19, x18, [x8], #16");
        asm volatile ("ldp x17, x16, [x8], #16");
        asm volatile ("ldp x15, x14, [x8], #16");
        asm volatile ("ldp x13, x12, [x8], #16");
        asm volatile ("ldp x11, x10, [x8], #16");
        asm volatile ("ldp x9, xzr, [x8], #16");
        asm volatile ("ldp x7, x6, [x8], #16");
        asm volatile ("ldp x5, x4, [x8], #16");
        asm volatile ("ldp x3, x2, [x8], #16");
        asm volatile ("ldp x1, x0, [x8], #16");
    }

    pub export fn restoreContextFromStack() callconv(.C) void {
        asm volatile ("ldp x30, x0, [sp, #16 * 0]");
        // asm volatile ("mov sp, x0");

        // x0: fp x1: pc
        asm volatile ("ldp x0, x1, [sp, #16 * 1]");
        asm volatile ("mov fp, x0");

        asm volatile ("ldp x28, x29, [sp, #16 * 2]");
        asm volatile ("ldp x26, x27, [sp, #16 * 3]");
        asm volatile ("ldp x24, x25, [sp, #16 * 4]");
        asm volatile ("ldp x22, x23, [sp, #16 * 5]");
        asm volatile ("ldp x20, x21, [sp, #16 * 6]");
        asm volatile ("ldp x18, x19, [sp, #16 * 7]");
        asm volatile ("ldp x16, x17, [sp, #16 * 8]");
        asm volatile ("ldp x14, x15, [sp, #16 * 9]");
        asm volatile ("ldp x12, x13, [sp, #16 * 10]");
        asm volatile ("ldp x10, x11, [sp, #16 * 11]");
        asm volatile ("ldp x8, x9, [sp, #16 * 12]");
        asm volatile ("ldp x6, x7, [sp, #16 * 13]");
        asm volatile ("ldp x4, x5, [sp, #16 * 14]");
        asm volatile ("ldp x2, x3, [sp, #16 * 15]");
        asm volatile ("ldp x0, x1, [sp, #16 * 16]");

        asm volatile ("add sp, sp, %[context_size]"
            :
            : [context_size] "rax" (@sizeOf(CpuContext)),
        );
    }

    pub export fn saveCurrContextOnStack(int_type: usize) callconv(.C) void {
        // todo => replace with sizeOf
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
        asm volatile ("mov x1, #0");
        asm volatile ("stp x0, x1, [sp, #16 * 16]");

        asm volatile ("mrs x0, far_el1");
        asm volatile ("mrs x1, esr_el1");
        asm volatile ("stp x0, x1, [sp, #16 * 17]");

        asm volatile ("mrs x0, CurrentEL");
        asm volatile ("stp x0, %[int_type], [sp, #16 * 18]"
            :
            : [int_type] "rax" (int_type),
        );
    }
};
