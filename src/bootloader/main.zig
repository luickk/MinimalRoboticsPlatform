const bl_utils = @import("utils.zig");
const intHandle = @import("intHandle.zig");
const proc = @import("peripherals").processor;
const kprint = @import("peripherals").serial.kprint;

export fn bl_main() callconv(.Naked) noreturn {

    // get address of external linker script variable which marks stack-top and kernel start
    const bl_stack_top: usize = @ptrToInt(@extern(?*u8, .{ .name = "_bl_stack_top", .linkage = .Strong }) orelse {
        kprint("error reading _stack_top label\n", .{});
        unreachable;
    });

    var current_el = proc.getCurrentEl();
    if (current_el != 1) {
        kprint("el must be 1! (it is: {d})\n", .{current_el});
        proc.panic();
    }
    kprint("bl setup mmu, el1, exc table \n", .{});

    var kernel_main = @intToPtr(*fn () noreturn, bl_stack_top + 1);
    // from now on addresses are translated

    // proc.enableMmu();
    kernel_main.*();

    unreachable;
}

comptime {
    @export(intHandle.irqHandler, .{ .name = "irqHandler", .linkage = .Strong });
    @export(intHandle.irqElxSpx, .{ .name = "irqElxSpx", .linkage = .Strong });
}
