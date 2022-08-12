const std = @import("std");
const kprint = @import("serial.zig").kprint;
const utils = @import("utils.zig");
const logger = @import("logger.zig");

// kernel services
const KernelAllocator = @import("memory.zig").KernelAllocator;
const intHandle = @import("intHandle.zig");
const intController = @import("intController.zig");
const timer = @import("timer.zig");
const proc = @import("processor.zig");

export fn kernel_main() callconv(.Naked) noreturn {
    // get address of external linker script variable which marks stack-top and heap-start
    const mem_start: usize = @ptrToInt(@extern(?*u8, .{ .name = "__stack_top" }) orelse {
        kprint("error reading _stack_top label\n", .{});
        unreachable;
    });

    var current_el = proc.getCurrentEl();
    if (current_el != 1) {
        kprint("el must be 1! (it is: {d})\n", .{current_el});
        proc.panic();
    }

    timer.initTimer();
    intController.initIc();

    var alloc = KernelAllocator(10000, 1000, 100).init(mem_start) catch |err| utils.printErrNoReturn(err);

    kprint("Memory: {d}; Pages: {d}, Chunk per Page: {d},\n", .{ alloc.kernel_mem.len, alloc.pages.len, alloc.pages[0].chunks.len });

    var p1 = alloc.alloc(u8, 875) catch |err| utils.printErrNoReturn(err);
    kprint("allocated slice: {*} \n", .{p1});
    var p2 = alloc.alloc(u8, 9) catch |err| utils.printErrNoReturn(err);
    kprint("allocated slice: {*} \n", .{p2});
    var p3 = alloc.alloc(u8, 43) catch |err| utils.printErrNoReturn(err);
    kprint("allocated slice: {*} \n", .{p3});
    var p4 = alloc.alloc(u8, 90) catch |err| utils.printErrNoReturn(err);
    kprint("allocated slice: {*} \n", .{p4});
    var p5 = alloc.alloc(u8, 156) catch |err| utils.printErrNoReturn(err);
    kprint("allocated slice: {*} \n", .{p5});
    var p6 = alloc.alloc(u8, 400) catch |err| utils.printErrNoReturn(err);
    kprint("allocated slice: {*} \n", .{p6});
    var p7 = alloc.alloc(u8, 875) catch |err| utils.printErrNoReturn(err);
    kprint("allocated slice: {*} \n", .{p7});
    logger.reportKMemStatus(&alloc);

    alloc.free(u8, p1) catch |err| utils.printErrNoReturn(err);
    alloc.free(u8, p2) catch |err| utils.printErrNoReturn(err);
    alloc.free(u8, p3) catch |err| utils.printErrNoReturn(err);
    alloc.free(u8, p4) catch |err| utils.printErrNoReturn(err);
    alloc.free(u8, p5) catch |err| utils.printErrNoReturn(err);
    alloc.free(u8, p6) catch |err| utils.printErrNoReturn(err);
    alloc.free(u8, p7) catch |err| utils.printErrNoReturn(err);

    logger.reportKMemStatus(&alloc);

    // proc.exceptionSvc();
    kprint("kernel boot complete \n", .{});
    while (true) {}
}

comptime {
    @export(intHandle.irqHandler, .{ .name = "irqHandler", .linkage = .Strong });
    @export(intHandle.irqElxSpx, .{ .name = "irqElxSpx", .linkage = .Strong });
}
