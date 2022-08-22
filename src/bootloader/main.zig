const bl_utils = @import("utils.zig");
const intHandle = @import("intHandle.zig");
const periph = @import("peripherals");
const proc = periph.processor;
const intController = periph.intController;
const kprint = periph.serial.kprint;

export fn bl_main() callconv(.Naked) noreturn {

    // const kernel_entry = @extern(?*fn () noreturn, .{ .name = "_kernelrom_start", .linkage = .Strong }) orelse {
    //     kprint("error reading _kernelrom_start label\n", .{});
    //     unreachable;
    // };

    // get address of external linker script variable which marks stack-top and kernel start
    const kernel_entry: usize = @ptrToInt(@extern(?*u8, .{ .name = "_kernelrom_start", .linkage = .Strong }) orelse {
        kprint("error reading _kernelrom_start label\n", .{});
        unreachable;
    });

    var current_el = proc.getCurrentEl();
    if (current_el != 1) {
        kprint("el must be 1! (it is: {d})\n", .{current_el});
        proc.panic();
    }
    kprint("bl setup mmu, el1, exc table. \n", .{});

    // set pc to kernel_entry
    proc.branchToAddr(kernel_entry);

    // from now on addresses are translated
    // proc.enableMmu();

    kprint("should not be reached \n", .{});
    unreachable;
}

comptime {
    @export(intHandle.irqHandler, .{ .name = "irqHandler", .linkage = .Strong });
    @export(intHandle.irqElxSpx, .{ .name = "irqElxSpx", .linkage = .Strong });
}
