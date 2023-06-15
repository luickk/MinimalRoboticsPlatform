const std = @import("std");

// global user required since timer is handleTimerIrq is called from the exception vector table
extern var scheduler: *Scheduler;

pub fn TimerKpi(
    comptime initTimer: fn (context: Context) !usize,
    comptime handleTimerTick: fn (context: Context) !usize,
    ) type {
    return struct {
        const Self = @This();
        // pub const Error = WriteError;

        pub fn init() Self {
            initTimer(self.context);
        }

        pub fn timerTick(self: *Self, irq_context: *CpuContext) !void {
            handleTimerTick(self.context);
            scheduler.timerIntEvent(irq_context);
        }
    };
}