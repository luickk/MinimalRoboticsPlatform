const std = @import("std");
const bl_utils = @import("utils.zig");
const intHandle = @import("intHandle.zig");
const periph = @import("peripherals");
const addr = periph.rbAddr;
const proc = periph.processor;
const intController = periph.intController;
const bprint = periph.serial.bprint;
const mmu = periph.mmu;

export fn bl_main() callconv(.Naked) noreturn {
    intController.initIc();

    // get address of external linker script variable which marks stack-top and kernel start
    const kernel_entry: usize = @ptrToInt(@extern(?*u8, .{ .name = "_kernelrom_start", .linkage = .Strong }) orelse {
        bprint("error reading _kernelrom_start label\n", .{});
        bl_utils.panic();
    });

    const kernel_end: usize = @ptrToInt(@extern(?*u8, .{ .name = "_kernelrom_end", .linkage = .Strong }) orelse {
        bprint("error reading _kernelrom_end label\n", .{});
        bl_utils.panic();
    });

    const _ttbr0_dir: usize = @ptrToInt(@extern(?*u8, .{ .name = "_ttbr0_dir", .linkage = .Strong }) orelse {
        bprint("error reading _ttbr0_dir label\n", .{});
        bl_utils.panic();
    });

    const _ttbr1_dir: usize = @ptrToInt(@extern(?*u8, .{ .name = "_ttbr1_dir", .linkage = .Strong }) orelse {
        bprint("error reading _ttbr1_dir label\n", .{});
        bl_utils.panic();
    });
    const kernel_size: usize = std.math.sub(usize, kernel_end, kernel_entry) catch {
        bprint("kernel size cacl error (probably a linker sizing issue) \n", .{});
        bl_utils.panic();
    };

    // @intToPtr(*u8, 0xd000).* = 0xFF;
    var kernel_bl: []u8 = undefined;
    kernel_bl.ptr = @intToPtr([*]u8, kernel_entry);
    kernel_bl.len = kernel_size;

    var kernel_target_loc: []u8 = undefined;
    kernel_target_loc.ptr = @intToPtr([*]u8, mmu.toSecure(usize, 0x20000000, null));
    kernel_target_loc.len = kernel_size;

    var current_el = proc.getCurrentEl();
    if (current_el != 1) {
        bprint("el must be 1! (it is: {d})\n", .{current_el});
        bl_utils.panic();
    }

    // MMU page dir config

    // writing to _id_mapped_dir(label) page table and creating new
    // identity mapped memory for bootloader to kernel transfer
    var ttbr0 = mmu.PageDir.init(.{ .base_addr = _ttbr0_dir, .page_shift = 12, .table_shift = 9 }) catch |e| {
        bprint("Page table init error, {s}\n", .{@errorName(e)});
        bl_utils.panic();
    };
    ttbr0.zeroPgDir();

    ttbr0.newTransLvl(.{ .trans_lvl = .first_lvl, .virt_start_addr = 0, .flags = mmu.MmuFlags.mmTypePageTable });
    ttbr0.newTransLvl(.{ .trans_lvl = .second_lvl, .virt_start_addr = 0, .flags = mmu.MmuFlags.mmTypePageTable });

    // identity mapped!
    ttbr0.populateTransLvl(.{ .trans_lvl = .third_lvl, .pop_type = .section, .virt_start_addr = 0, .virt_end_addr = 18446462599804485632, .phys_addr = 0, .flags = mmu.MmuFlags.mmuFlags });

    // creating virtual address space for kernel
    var ttbr1 = mmu.PageDir.init(.{ .base_addr = _ttbr1_dir, .page_shift = 12, .table_shift = 9 }) catch |e| {
        bprint("Page table init error, {s}\n", .{@errorName(e)});
        bl_utils.panic();
    };
    ttbr1.zeroPgDir();
    ttbr1.newTransLvl(.{ .trans_lvl = .first_lvl, .virt_start_addr = addr.vaStart, .flags = mmu.MmuFlags.mmTypePageTable });
    ttbr1.newTransLvl(.{ .trans_lvl = .second_lvl, .virt_start_addr = addr.vaStart, .flags = mmu.MmuFlags.mmTypePageTable });

    ttbr1.populateTransLvl(.{ .trans_lvl = .third_lvl, .pop_type = .section, .virt_start_addr = addr.vaStart, .virt_end_addr = 18446462599787708416, .phys_addr = 0, .flags = mmu.MmuFlags.mmuFlags });
    ttbr1.populateTransLvl(.{ .trans_lvl = .third_lvl, .pop_type = .section, .virt_start_addr = addr.vaStart + addr.rpBase, .virt_end_addr = 18446462599804485632, .phys_addr = addr.rpBase, .flags = mmu.MmuFlags.mmuFlags });

    proc.isb();

    // MMU page dir config

    bprint("[bootloader] enabling mmu... \n", .{});
    proc.enableMmu();

    bprint("[bootloader] setup mmu, el1, exc table. \n", .{});
    bprint("[bootloader] Copying kernel to secure: 0x{x}, with size: {d} \n", .{ @ptrToInt(kernel_target_loc.ptr), kernel_target_loc.len });
    std.mem.copy(u8, kernel_target_loc, kernel_bl);

    bprint("[bootloader] kernel copied \n", .{});

    bprint("[bootloader] jumping to secure kernel copy \n", .{});
    proc.branchToAddr(@ptrToInt(kernel_target_loc.ptr));

    while (true) {}
}

comptime {
    @export(intHandle.irqHandler, .{ .name = "irqHandler", .linkage = .Strong });
    @export(intHandle.irqElxSpx, .{ .name = "irqElxSpx", .linkage = .Strong });
}
