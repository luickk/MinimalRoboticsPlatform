const std = @import("std");
const bl_utils = @import("utils.zig");
const intHandle = @import("intHandle.zig");
const periph = @import("peripherals");
const proc = periph.processor;
const intController = periph.intController;
const kprint = periph.serial.kprint;
const mmu = periph.mmu;

export fn bl_main() callconv(.Naked) noreturn {
    intController.initIc();

    // proc.exceptionSvc();

    // get address of external linker script variable which marks stack-top and kernel start
    const kernel_entry: usize = @ptrToInt(@extern(?*u8, .{ .name = "_kernelrom_start", .linkage = .Strong }) orelse {
        kprint("error reading _kernelrom_start label\n", .{});
        unreachable;
    });

    const kernel_end: usize = @ptrToInt(@extern(?*u8, .{ .name = "_kernelrom_end", .linkage = .Strong }) orelse {
        kprint("error reading _kernelrom_end label\n", .{});
        unreachable;
    });
    const kernel_size: usize = std.math.sub(usize, kernel_end, kernel_entry) catch {
        kprint("kernel size cacl error \n", .{});
        unreachable;
    };
    // kprint("size: {d} \n", .{kernel_size});

    var kernel: []u8 = undefined;
    kernel.ptr = @intToPtr([*]u8, kernel_entry);
    kernel.len = kernel_size;

    var kernel_target_loc: []u8 = undefined;
    kernel_target_loc.ptr = @intToPtr([*]u8, mmu.kernelPh2Virt(0x20000000));
    kernel_target_loc.len = kernel_size;

    var current_el = proc.getCurrentEl();
    if (current_el != 1) {
        kprint("el must be 1! (it is: {d})\n", .{current_el});
        proc.panic();
    }

    proc.enableMmu();

    kprint("[bootloader] setup mmu, el1, exc table. \n", .{});
    kprint("[bootloader] Copying kernel to secure: 0x{x}, with size: {d} \n", .{ @ptrToInt(kernel_target_loc.ptr), kernel_target_loc.len });
    std.mem.copy(u8, kernel_target_loc, kernel);
    kprint("[bootloader] kernel copied \n", .{});

    kprint("[bootloader] jumping to secure kernel copy \n", .{});
    proc.branchToAddr(@ptrToInt(kernel_target_loc.ptr));

    // kprint("should not be reached \n", .{});

    while (true) {}
}

comptime {
    @export(intHandle.irqHandler, .{ .name = "irqHandler", .linkage = .Strong });
    @export(intHandle.irqElxSpx, .{ .name = "irqElxSpx", .linkage = .Strong });
}
