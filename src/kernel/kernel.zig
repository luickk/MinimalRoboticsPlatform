const std = @import("std");
const periph = @import("peripherals");

const kprint = periph.serial.kprint;
// const utils = @import("utils.zig");
// const logger = @import("logger.zig");
// const tests = @import("tests.zig");

// kernel services
// const KernelAllocator = @import("memory.zig").KernelAllocator;
const intHandle = @import("intHandle.zig");
// const intController = periph.intController;
// const timer = periph.timer;
// const proc = periph.processor;
const mmu = periph.mmu;

export fn kernel_main() callconv(.Naked) noreturn {
    // get address of external linker script variable which marks stack-top and heap-start
    // const mem_start: usize = @ptrToInt(@extern(?*u8, .{ .name = "_stack_top" }) orelse {
    //     kprint("error reading _stack_top label\n", .{});
    //     unreachable;
    // });

    // var current_el = proc.getCurrentEl();
    // if (current_el != 1) {
    //     kprint("el must be 1! (it is: {d})\n", .{current_el});
    //     proc.panic();
    // }
    kprint("el 1 \n", .{});

    // timer.initTimer();
    // kprint("timer inited \n", .{});
    // intController.initIc();
    // kprint("ic inited \n", .{});

    // var alloc = KernelAllocator(5000000, 512).init(mem_start) catch |err| utils.printErrNoReturn(err);
    // _ = alloc;
    // kprint("kernel allocator inited \n", .{});

    // // tests.testKMalloc(&alloc);
    // // logger.reportKMemStatus(&alloc);

    // // proc.exceptionSvc();
    mmu.testc();
    // kprint("kernel boot complete \n", .{});
    while (true) {}
}

comptime {
    @export(intHandle.irqHandler, .{ .name = "irqHandler", .linkage = .Strong });
    @export(intHandle.irqElxSpx, .{ .name = "irqElxSpx", .linkage = .Strong });
}
