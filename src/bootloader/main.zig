const bl_utils = @import("utils.zig");
const intHandle = @import("intHandle.zig");
const serial = @import("peripherals").serial;

export fn bl_main() callconv(.Naked) noreturn {
    serial.kprint("test", .{});
    // lastly enable mmu and switch to kernel
    unreachable;
}

comptime {
    @export(intHandle.irqHandler, .{ .name = "irqHandler", .linkage = .Strong });
    @export(intHandle.irqElxSpx, .{ .name = "irqElxSpx", .linkage = .Strong });
}
