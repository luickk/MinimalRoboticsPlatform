const sharedKernelServices = @import("sharedKernelServices");
const Scheduler = sharedKernelServices.Scheduler;

const Thread = fn (scheduler: *Scheduler) noreturn;

pub const testThread = @import("testThread.zig");

// threads array is loaded and inited by the kernel
pub const threads = [_]Thread{testThread.threadFn};
