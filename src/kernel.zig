const kprint = @import("serial.zig").kprint;
const utils = @import("utils.zig");

const intHandle = @import("intHandle.zig");

export fn kernel_main() callconv(.Naked) noreturn {
    // get address of external linker script variable which marks stack-top and heap-start
    const heap_start: usize = @ptrToInt(@extern(?*u8, .{ .name = "_end" }) orelse {
        kprint("error reading _stack_top label\n", .{});
        unreachable;
    });
    _ = heap_start;

    kprint("kernel boot complete \n", .{});
    while (true) {}
}

comptime {
    @export(intHandle.irq_handler, .{ .name = "irq_handler", .linkage = .Strong });
    @export(intHandle.irq_elx_spx, .{ .name = "irq_elx_spx", .linkage = .Strong });
}
