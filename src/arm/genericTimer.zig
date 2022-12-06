const std = @import("std");
const mmu = @import("mmu.zig");
const AddrSpace = @import("board").boardConfig.AddrSpace;
const Scheduler = sharedKServices.Scheduler;
const CpuContext = @import("cpuContext.zig").CpuContext;
const sharedKServices = @import("sharedKServices");

extern var scheduler: *Scheduler;

var timerVal: usize = 0;

var cnt_freq: usize = 0;

// initialize gic controller
pub fn setupGt() void {
    cnt_freq = asm ("mrs %[curr], CNTFRQ_EL0"
        : [curr] "=r" (-> usize),
    );
    timerVal = cnt_freq;

    var freq = cnt_freq * 1;
    timerVal += freq;

    asm volatile (
        \\msr CNTP_TVAL_EL0, %[freq]
        \\mov x0, 1
        \\msr cntp_ctl_el0, x0
        :
        : [freq] "r" (timerVal),
        : "x0"
    );
}

pub fn timerInt(irq_context: *CpuContext) void {
    timerVal += cnt_freq;
    asm volatile (
        \\msr CNTP_TVAL_EL0, %[freq]
        \\mov x0, 1
        \\msr cntp_ctl_el0, x0
        :
        : [freq] "r" (timerVal),
        : "x0"
    );

    scheduler.timerIntEvent(irq_context);
}
