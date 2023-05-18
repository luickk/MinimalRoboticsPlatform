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

var cnt_freq: usize = 0;

pub fn getFreq() usize {
    return asm ("mrs %[curr], CNTFRQ_EL0"
        : [curr] "=r" (-> usize),
    );
}

// initialize gic controller
pub fn setupGt() !void {
    cnt_freq = asm ("mrs %[curr], CNTFRQ_EL0"
        : [curr] "=r" (-> usize),
    );
    timerVal += try utils.calcTicksFromHertz(cnt_freq, board.config.scheduler_freq_in_hertz);

    kprint("timer val: {d} \n", .{timerVal});
    asm volatile (
        \\msr CNTP_CVAL_EL0, %[cval]
        \\mov x0, 1
        \\msr cntp_ctl_el0, x0
        :
        : [cval] "r" (timerVal),
        : "x0"
    );
}

pub fn timerInt(irq_context: *CpuContext) !void {
    const ticks = try utils.calcTicksFromHertz(cnt_freq, board.config.scheduler_freq_in_hertz);
    if (@addWithOverflow(usize, timerVal, ticks, &timerVal)) timerVal = 0;

    asm volatile (
        \\msr CNTP_CVAL_EL0, %[cval]
        \\mov x0, 1
        \\msr cntp_ctl_el0, x0
        :
        : [cval] "r" (timerVal),
        : "x0"
    );

    scheduler.timerIntEvent(irq_context);
}
