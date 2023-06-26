const sharedKernelServices = @import("sharedKernelServices");
const Scheduler = sharedKernelServices.Scheduler;


pub const bcm2835IrqHandler = @import("bcm2835IrqHandler.zig");

pub fn registerKernelThreads(args: anytype) ![1]thread_init_runtime {
	// just add every new thread to this array
	return [_]thread_init_runtime{ try initThread(bcm2835IrqHandler.threadFn, args) };	
}

const thread_init_runtime = struct {
	entry_fn: *const anyopaque,
	thread_fn_ptr: *const anyopaque,
	arg_mem: []const u8,
	arg_size: usize,
};

fn initThread(thread_fn: anytype, args: anytype) !thread_init_runtime {
    var arg_mem: []const u8 = undefined;
    arg_mem.ptr = @ptrCast([*]const u8, @alignCast(1, &args));
    arg_mem.len = @sizeOf(@TypeOf(args));

    const entry_fn = &(Scheduler.KernelThreadInstance(thread_fn, @TypeOf(args)).threadEntry);
    var thread_fn_ptr = &thread_fn;
    return .{ .entry_fn = @ptrCast(*const anyopaque, entry_fn), .thread_fn_ptr = @ptrCast(*const anyopaque, thread_fn_ptr), .arg_mem = arg_mem, .arg_size = @sizeOf(@TypeOf(args))};
}