const std = @import("std");
const bl_utils = @import("utils.zig");
const intHandle = @import("gicHandle.zig");
const periph = @import("peripherals");
const board = @import("board");
const b_options = @import("build_options");
const proc = periph.processor;
const bprint = periph.serial.bprint;
const mmu = periph.mmu;

// raspberry
const bcm2835IntController = periph.bcm2835IntController;

const gic = periph.gicv2;

const Granule = board.layout.Granule;
const GranuleParams = board.layout.GranuleParams;
const TransLvl = board.layout.TransLvl;

const kernel_bin_size = b_options.kernel_bin_size;

export fn bl_main() callconv(.Naked) noreturn {
    if (board.Info.board == .raspi3b)
        bcm2835IntController.initIc();

    // GIC Init
    if (board.Info.board == .virt)
        gic.gicv2Initialize();

    // get address of external linker script variable which marks stack-top and kernel start
    const kernel_entry: usize = @ptrToInt(@extern(?*u8, .{ .name = "_kernelrom_start", .linkage = .Strong }) orelse {
        bprint("error reading _kernelrom_start label\n", .{});
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

    // @intToPtr(*u8, 0xd000).* = 0xFF;
    var kernel_bl: []u8 = undefined;
    kernel_bl.ptr = @intToPtr([*]u8, kernel_entry);
    kernel_bl.len = kernel_bin_size;

    var kernel_target_loc: []u8 = undefined;
    kernel_target_loc.ptr = @intToPtr([*]u8, mmu.toSecure(usize, board.Info.mem.ram_start_addr));
    kernel_target_loc.len = kernel_bin_size;

    var current_el = proc.getCurrentEl();
    if (current_el != 1) {
        bprint("[panic] el must be 1! (it is: {d})\n", .{current_el});
        bl_utils.panic();
    }

    // MMU page dir config

    // writing to _id_mapped_dir(label) page table and creating new
    // identity mapped memory for bootloader to kernel transfer
    const bootloader_mapping = mmu.Mapping{ .mem_size = board.Info.mem.rom_len, .virt_start_addr = 0, .phys_addr = board.Info.mem.rom_start_addr, .granule = Granule.Section, .flags = mmu.TableEntryAttr{ .accessPerm = .only_el1_read_write, .descType = .block } };
    // identity mapped memory for bootloader and kernel contrtol handover!
    var ttbr0 = (mmu.PageDir(bootloader_mapping) catch |e| {
        @compileError(@errorName(e));
    }).init(_ttbr0_dir) catch |e| {
        bprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
        bl_utils.panic();
    };
    ttbr0.mapMem() catch |e| {
        bprint("[panic] memory mapping error: {s} \n", .{@errorName(e)});
        bl_utils.panic();
    };

    // creating virtual address space for kernel
    const kernel_mapping = mmu.Mapping{ .mem_size = board.Info.mem.ram_len, .virt_start_addr = board.Addresses.vaStart, .phys_addr = board.Info.mem.ram_start_addr, .granule = Granule.Section, .flags = mmu.TableEntryAttr{ .accessPerm = .only_el1_read_write, .descType = .block } };
    // mapping general kernel mem (inlcuding device base)
    var ttbr1 = (mmu.PageDir(kernel_mapping) catch |e| {
        @compileError(@errorName(e));
    }).init(_ttbr1_dir) catch |e| {
        bprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
        bl_utils.panic();
    };
    ttbr1.mapMem() catch |e| {
        bprint("[panic] memory mapping error: {s} \n", .{@errorName(e)});
        bl_utils.panic();
    };

    // MMU page dir config

    proc.isb();

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

export const _mairVal = (mmu.MairReg{ .attr1 = 4, .attr2 = 4 }).asInt();
// t0sz: The size offset of the memory region addressed by TTBR0_EL1
// t1sz: The size offset of the memory region addressed by TTBR1_EL1
// tg0: Granule size for the TTBR0_EL1.
// tg1 not required since it's sections
export const _tcrVal = (mmu.TcrReg{ .t0sz = 16, .t1sz = 16 }).asInt();

comptime {
    @export(intHandle.irqHandler, .{ .name = "irqHandler", .linkage = .Strong });
    @export(intHandle.irqElxSpx, .{ .name = "irqElxSpx", .linkage = .Strong });
}
