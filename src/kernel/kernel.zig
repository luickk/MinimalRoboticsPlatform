const std = @import("std");
const periph = @import("peripherals");
const utils = @import("utils");

const kprint = periph.serial.kprint;
// kernel services
const KernelAllocator = @import("memory.zig").KernelAllocator;
const intHandle = @import("intHandle.zig");
const intController = periph.intController;
const timer = periph.timer;
const proc = periph.processor;
const mmu = periph.mmu;

export fn kernel_main() callconv(.Naked) noreturn {
    kprint("kernel started! \n", .{});

    // get address of external linker script variable which marks stack-top and heap-start
    const mem_start: usize = @ptrToInt(@extern(?*u8, .{ .name = "_stack_top" }) orelse {
        kprint("error reading _stack_top label\n", .{});
        unreachable;
    });

    var current_el = proc.getCurrentEl();
    if (current_el != 1) {
        kprint("el must be 1! (it is: {d})\n", .{current_el});
        proc.panic();
    }

    timer.initTimer();
    kprint("timer inited \n", .{});
    intController.initIc();
    kprint("ic inited \n", .{});

    var alloc = KernelAllocator(5000000, 512).init(mem_start) catch |err| utils.printErrNoReturn(err);
    _ = alloc;
    kprint("kernel allocator inited \n", .{});

    // tests.testKMalloc(&alloc);
    // logger.reportKMemStatus(&alloc);

    // proc.exceptionSvc();

    kprint("kernel boot complete \n", .{});
    while (true) {}
}
