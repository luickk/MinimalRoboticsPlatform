const std = @import("std");
const kprint = @import("serial.zig").kprint;
const utils = @import("utils.zig");
const logger = @import("logger.zig");
const tests = @import("tests.zig");

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
    kprint("el 2 \n", .{});

    timer.initTimer();
    kprint("timer inited \n", .{});
    intController.initIc();
    kprint("ic inited \n", .{});

    var alloc = KernelAllocator(5000000, 4096, 512).init(mem_start) catch |err| utils.printErrNoReturn(err);
    kprint("kernel allocator inited \n", .{});

    kprint("Memory: {d}; Pages: {d}, Chunk per Page: {d},\n", .{ alloc.kernel_mem.len, alloc.pages.len, alloc.pages[0].chunks.len });
    // tests.testKMalloc(&alloc);
    // logger.reportKMemStatus(&alloc);

    // proc.exceptionSvc();
    kprint("kernel boot complete \n", .{});
    while (true) {}
}

comptime {
    @export(intHandle.irqHandler, .{ .name = "irqHandler", .linkage = .Strong });
    @export(intHandle.irqElxSpx, .{ .name = "irqElxSpx", .linkage = .Strong });
}
