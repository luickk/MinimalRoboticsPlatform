const sharedKernelServices = @import("sharedKernelServices");
const Scheduler = sharedKernelServices.Scheduler;


pub const testThread = @import("testThread.zig");

// threads array is loaded and inited by the kernel 
pub const threads = [_]fn (scheduler: *Scheduler) noreturn{ testThread.threadFn };