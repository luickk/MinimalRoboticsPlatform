const std = @import("std");

const Scheduler = @import("sharedKernelServices").Scheduler;
const arm = @import("arm");
const CpuContext = arm.cpuContext.CpuContext;


// global user required since timer is handleTimerIrq is called from the exception vector table
extern var scheduler: *Scheduler;

pub fn TimerKpi(
    comptime Context: type,
    comptime TimerError: type,
    comptime initTimer: fn (context: Context) TimerError!void,
    comptime handleTimerTick: fn (context: Context) TimerError!void,
    ) type {
    return struct {
        const Self = @This();
        pub const Error = TimerError;
        
        context: Context,
        
        pub fn init(context: Context) Self {
            return .{
                .context = context,
            };
        }
        pub fn initTimerDriver(self: Self) Error!void {
            try initTimer(self.context);
        }

        pub fn timerTick(self: Self, irq_context: *CpuContext) Error!void {
            try handleTimerTick(self.context);
            scheduler.timerIntEvent(irq_context);
        }
    };
}