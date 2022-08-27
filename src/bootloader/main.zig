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
    // const kernel_entry = @extern(?*fn () noreturn, .{ .name = "_kernelrom_start", .linkage = .Strong }) orelse {
    //     kprint("error reading _kernelrom_start label\n", .{});
    //     unreachable;
    // };

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
    var kernel = @ptrCast(*[]u8, &.{ .ptr = @intToPtr(*u8, kernel_entry), .len = kernel_size }).*;
    var kernel_target_loc = @ptrCast(*[]u8, &.{ .ptr = 0xffff000000000000, .len = kernel_size }).*;
    _ = kernel;
    _ = kernel_target_loc;

    var current_el = proc.getCurrentEl();
    if (current_el != 1) {
        kprint("el must be 1! (it is: {d})\n", .{current_el});
        proc.panic();
    }

    // proc.exceptionSvc();

    kprint("[bootloader] setup mmu, el1, exc table. \n", .{});

    // std.mem.copy(u8, kernel_target_loc, kernel);

    // kprint("[bootloader] kernel copied \n", .{});

    // from now on addresses are translated
    // proc.enableMmu();

    // set pc to kernel_entry
    proc.branchToAddr(kernel_entry);

    // kprint("should not be reached \n", .{});

    while (true) {}
}

comptime {
    @export(intHandle.irqHandler, .{ .name = "irqHandler", .linkage = .Strong });
    @export(intHandle.irqElxSpx, .{ .name = "irqElxSpx", .linkage = .Strong });
}
