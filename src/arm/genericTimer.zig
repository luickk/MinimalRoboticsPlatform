const std = @import("std");
const mmu = @import("mmu.zig");
const AddrSpace = @import("board").boardConfig.AddrSpace;

// initialize gic controller
pub fn setupGt() void {
    asm volatile ("mrs x1, CNTFRQ_EL0");
    asm volatile ("mov x4, #2");
    asm volatile ("mul x3, x1, x4");
    asm volatile ("msr CNTP_TVAL_EL0, x3");

    asm volatile ("mrs x2, cntvct_el0");
    asm volatile ("add x3, x1, x2");

    asm volatile ("mov x0, 1");
    asm volatile ("msr cntp_ctl_el0, x0");
}
