const std = @import("std");
const mmu = @import("mmu.zig");
const AddrSpace = @import("board").boardConfig.AddrSpace;

// initialize gic controller
pub fn setupGt() void {
    asm volatile ("mrs x1, cntfrq_el0");
    asm volatile ("msr cntp_tval_el0, x1");
    asm volatile ("mov x0, 1");
    asm volatile ("msr cntp_ctl_el0, x0");
}
