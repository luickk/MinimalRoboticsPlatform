const kprint = @import("serial.zig").kprint;
const utils = @import("utils.zig");

const intHandle = @import("intHandle.zig");
const intController = @import("intController.zig");
const timer = @import("timer.zig");
const proc = @import("processor.zig");

export fn kernel_main() callconv(.Naked) noreturn {
    // get address of external linker script variable which marks stack-top and heap-start
    const heap_start: usize = @ptrToInt(@extern(?*u8, .{ .name = "_end" }) orelse {
        kprint("error reading _stack_top label\n", .{});
        unreachable;
    });
    _ = heap_start;
    var current_el = proc.getCurrentEl();
    if (current_el != 1) {
        kprint("el must be 1! (it is: {d})\n", .{current_el});
        proc.panic();
    }

    timer.initTimer();
    intController.initIc();

    proc.exceptionSvc();

    kprint("kernel boot complete \n", .{});
    while (true) {}
}

comptime {
    @export(intHandle.irqHandler, .{ .name = "irqHandler", .linkage = .Strong });
    @export(intHandle.irqElxSpx, .{ .name = "irqElxSpx", .linkage = .Strong });
}
