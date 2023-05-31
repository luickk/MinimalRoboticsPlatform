const std = @import("std");
const mmu = @import("mmu.zig");
const periph = @import("periph");
const utils = @import("utils");
const board = @import("board");
const AddrSpace = @import("board").boardConfig.AddrSpace;
const Scheduler = sharedKernelServices.Scheduler;
const CpuContext = @import("cpuContext.zig").CpuContext;
const sharedKernelServices = @import("sharedKernelServices");

const kprint = periph.uart.UartWriter(.ttbr1).kprint;

extern var scheduler: *Scheduler;

var timerVal: usize = 0;

pub fn getFreq() usize {
    return asm ("mrs %[curr], CNTFRQ_EL0"
        : [curr] "=r" (-> usize),
    );
}

// initialize gic controller
pub fn setupGt() !void {
    const cnt_freq = getFreq();

    const increasePerTick = try utils.calcTicksFromHertz(cnt_freq, board.config.scheduler_freq_in_hertz);

    timerVal += increasePerTick;
    asm volatile (
        \\msr CNTP_TVAL_EL0, %[cval]
        \\mov x0, 1
        \\msr cntp_ctl_el0, x0
        :
        : [cval] "r" (timerVal),
        : "x0"
    );
}

pub fn timerInt(irq_context: *CpuContext) !void {
    asm volatile (
        \\msr CNTP_TVAL_EL0, %[cval]
        \\mov x0, 1
        \\msr cntp_ctl_el0, x0
        :
        : [cval] "r" (timerVal),
        : "x0"
    );

    scheduler.timerIntEvent(irq_context);
}
