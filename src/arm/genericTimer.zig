const std = @import("std");
const mmu = @import("mmu.zig");
const periph = @import("periph");
const utils = @import("utils");
const AddrSpace = @import("board").boardConfig.AddrSpace;
const Scheduler = sharedKernelServices.Scheduler;
const CpuContext = @import("cpuContext.zig").CpuContext;
const sharedKernelServices = @import("sharedKernelServices");

const kprint = periph.uart.UartWriter(.ttbr1).kprint;

extern var scheduler: *Scheduler;

var timerVal: usize = 0;

var freq_factor: f64 = 0.02;

var cnt_freq: usize = 0;

// todo => handle timer overflow

pub fn getFreq() usize {
    return asm ("mrs %[curr], CNTFRQ_EL0"
        : [curr] "=r" (-> usize),
    );
}

// initialize gic controller
pub fn setupGt() void {
    cnt_freq = asm ("mrs %[curr], CNTFRQ_EL0"
        : [curr] "=r" (-> usize),
    );
    timerVal += utils.calcTicksFromSeconds(cnt_freq, freq_factor);

    asm volatile (
        \\msr CNTP_CVAL_EL0, %[freq]
        \\mov x0, 1
        \\msr cntp_ctl_el0, x0
        :
        : [freq] "r" (timerVal),
        : "x0"
    );
}

pub fn timerInt(irq_context: *CpuContext) void {
    timerVal += utils.calcTicksFromSeconds(cnt_freq, freq_factor);
    asm volatile (
        \\msr CNTP_CVAL_EL0, %[freq]
        \\mov x0, 1
        \\msr cntp_ctl_el0, x0
        :
        : [freq] "r" (timerVal),
        : "x0"
    );

    scheduler.timerIntEvent(irq_context);
}
