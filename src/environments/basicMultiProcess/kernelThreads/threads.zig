const sharedKernelServices = @import("sharedKernelServices");
const Scheduler = sharedKernelServices.Scheduler;


pub const testThread = @import("testThread.zig");

// if you want to add another kernel thrad, just add it to the array and it will get inited at kernel setup
pub const threads = [_]fn (scheduler: *Scheduler) noreturn{ testThread.threadFn };