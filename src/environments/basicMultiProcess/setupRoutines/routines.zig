const sharedKernelServices = @import("sharedKernelServices");
const Scheduler = sharedKernelServices.Scheduler;


pub const bcm2835IrqHandler = @import("bcm2835IrqHandler.zig");
pub const bcm2835Timer = @import("bcm2835Timer.zig");


pub const setupRoutines = [_]fn (scheduler: *Scheduler) void{ bcm2835IrqHandler.bcm2835IrqHandlerSetup, bcm2835Timer.bcm2835TimerSetup };