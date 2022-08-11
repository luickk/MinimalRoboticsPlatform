const kprint = @import("serial.zig").kprint;
const utils = @import("utils.zig");

// kernel services
const KernelAllocator = @import("memory.zig").KernelAllocator;
const intHandle = @import("intHandle.zig");
const intController = @import("intController.zig");
const timer = @import("timer.zig");
const proc = @import("processor.zig");

export fn kernel_main() callconv(.Naked) noreturn {
    // get address of external linker script variable which marks stack-top and heap-start
    const mem_start: usize = @ptrToInt(@extern(?*u8, .{ .name = "_end" }) orelse {
        kprint("error reading _stack_top label\n", .{});
        unreachable;
    });
    _ = mem_start;
    var current_el = proc.getCurrentEl();
    if (current_el != 1) {
        kprint("el must be 1! (it is: {d})\n", .{current_el});
        proc.panic();
    }

    timer.initTimer();
    intController.initIc();

    var alloc = KernelAllocator(100000, 10000, 1000, 100000).init(mem_start) catch |err| {
        kprint("allocator error: {s} \n", .{@errorName(err)});
        unreachable;
    };

    // _ = alloc.allocU8(100) catch |err| {
    //     kprint("allocator error: {s} \n", .{@errorName(err)});
    //     unreachable;
    // };
    // _ = alloc.allocU8(100) catch |err| {
    //     kprint("allocator error: {s} \n", .{@errorName(err)});
    //     unreachable;
    // };
    // _ = alloc.allocU8(500) catch |err| {
    //     kprint("allocator error: {s} \n", .{@errorName(err)});
    //     unreachable;
    // };
    // _ = alloc.allocU8(1000) catch |err| {
    //     kprint("allocator error: {s} \n", .{@errorName(err)});
    //     unreachable;
    // };
    // _ = alloc.allocU8(30) catch |err| {
    //     kprint("allocator error: {s} \n", .{@errorName(err)});
    //     unreachable;
    // };
    // _ = alloc.allocU8(800) catch |err| {
    //     kprint("allocator error: {s} \n", .{@errorName(err)});
    //     unreachable;
    // };
    // _ = alloc.allocU8(100) catch |err| {
    //     kprint("allocator error: {s} \n", .{@errorName(err)});
    //     unreachable;
    // };
    var p = alloc.allocU8(100) catch |err| {
        kprint("allocator error: {s} \n", .{@errorName(err)});
        unreachable;
    };
    alloc.free(p);
    // proc.exceptionSvc();

    kprint("kernel boot complete \n", .{});
    while (true) {}
}

comptime {
    @export(intHandle.irqHandler, .{ .name = "irqHandler", .linkage = .Strong });
    @export(intHandle.irqElxSpx, .{ .name = "irqElxSpx", .linkage = .Strong });
}
