const std = @import("std");
const bl_utils = @import("utils.zig");
const intHandle = @import("gicHandle.zig");
const periph = @import("peripherals");
const board = @import("board");
const b_options = @import("build_options");
const proc = periph.processor;
const bprint = periph.serial.bprint;
const mmuComp = periph.mmuComptime;
const mmu = periph.mmu;

// raspberry
const bcm2835IntController = periph.bcm2835IntController;

const gic = periph.gicv2;

const Granule = board.layout.Granule;
const GranuleParams = board.layout.GranuleParams;
const TransLvl = board.layout.TransLvl;

const kernel_bin_size = b_options.kernel_bin_size;

// const static_ttbr: [
//     board.Info.mem.calcPageTableSizeRom() catch |e| {
//         @compileError(@errorName(e));
//     }
// ]usize = undefined;

const bl_page_tables = blk: {
    @setEvalBranchQuota(1000000);
    const ttbr1_size = board.Info.mem.calcPageTableSizeRam() catch |e| {
        @compileError(@errorName(e));
    };

    // ttbr0 (rom) mapps both rom and ram
    const ttbr0_size = (board.Info.mem.calcPageTableSizeRom() catch |e| {
        @compileError(@errorName(e));
    });

    var ttbr0_arr: [ttbr0_size]usize = [_]usize{0} ** ttbr0_size;
    var ttbr1_arr: [ttbr1_size]usize = [_]usize{0} ** ttbr1_size;

    // in case there is no rom(rom_len is equal to zero) and the kernel(and bl) are directly loaded to memory by some rom bootloader
    // the ttbr0 memory is also identity mapped to the ram
    var rom_len: usize = undefined;
    var rom_start_addr: usize = undefined;
    if (board.Info.mem.rom_len == 0) {
        rom_len = board.Info.mem.ram_len;
        rom_start_addr = board.Info.mem.ram_start_addr;
    } else {
        rom_len = board.Info.mem.rom_len + board.Info.mem.ram_len;
        rom_start_addr = board.Info.mem.rom_start_addr;
    }

    // MMU page dir config

    // writing to _id_mapped_dir(label) page table and creating new
    // identity mapped memory for bootloader to kernel transfer
    const bootloader_mapping = mmuComp.Mapping{ .mem_size = rom_len, .virt_start_addr = 0, .phys_addr = rom_start_addr, .granule = Granule.Section, .flags = mmuComp.TableEntryAttr{ .accessPerm = .only_el1_read_write, .descType = .block } };
    // identity mapped memory for bootloader and kernel contrtol handover!
    var ttbr0 = (mmuComp.PageDir(bootloader_mapping) catch |e| {
        @compileError(@errorName(e));
    }).init(&ttbr0_arr) catch |e| {
        @compileError(@errorName(e));
    };
    ttbr0.mapMem() catch |e| {
        @compileError(@errorName(e));
    };

    // creating virtual address space for kernel
    const kernel_mapping = mmuComp.Mapping{ .mem_size = board.Info.mem.ram_len, .virt_start_addr = board.Addresses.vaStart, .phys_addr = board.Info.mem.ram_start_addr, .granule = Granule.Section, .flags = mmuComp.TableEntryAttr{ .accessPerm = .only_el1_read_write, .descType = .block } };
    // mapping general kernel mem (inlcuding device base)
    var ttbr1 = (mmuComp.PageDir(kernel_mapping) catch |e| {
        @compileError(@errorName(e));
    }).init(&ttbr1_arr) catch |e| {
        @compileError(@errorName(e));
    };
    ttbr1.mapMem() catch |e| {
        @compileError(@errorName(e));
    };

    break :blk .{ ttbr0_arr, ttbr1_arr };
};

// note: when bl_main gets too bit(instruction mem wise), the exception vector table could be pushed too far up and potentially not be read!
export fn bl_main() callconv(.Naked) noreturn {
    bprint("{s} \n", .{bl_page_tables});

    if (board.Info.board == .qemuRaspi3b or board.Info.board == .raspi3b)
        bcm2835IntController.initIc();

    // GIC Init
    if (board.Info.board == .qemuVirt)
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

    var kernel_bl: []u8 = undefined;
    kernel_bl.ptr = @intToPtr([*]u8, kernel_entry);
    kernel_bl.len = kernel_bin_size;

    var kernel_target_loc: []u8 = undefined;
    kernel_target_loc.ptr = @intToPtr([*]u8, mmu.toSecure(usize, board.Info.mem.ram_start_addr));
    kernel_target_loc.len = kernel_bin_size;

    // todo => check for security state!

    var current_el = proc.getCurrentEl();
    if (current_el != 1) {
        bprint("[panic] el must be 1! (it is: {d})\n", .{current_el});
        bl_utils.panic();
    }

    // writing page dirs to ram, in case we boot from rom!
    // todo => make page dir generation comptime and static! (currently prevented by max array size)

    // const _ttbr1_dir = board.Info.mem.ram_start_addr + kernel_bin_size;
    // const _ttbr0_dir = _ttbr1_dir + (board.Info.mem.calcPageTableSizeRam() catch |e| {
    //     bprint("[panic] Page table ram address calc error: {s}\n", .{@errorName(e)});
    //     bl_utils.panic();
    // });
    bprint("ttbr0: {x}, ttbr1: {x} \n", .{ _ttbr0_dir, _ttbr1_dir });

    // in case there is no rom(rom_len is equal to zero) and the kernel(and bl) are directly loaded to memory by some rom bootloader
    // the ttbr0 memory is also identity mapped to the ram
    comptime var rom_len: usize = undefined;
    comptime var rom_start_addr: usize = undefined;
    if (board.Info.mem.rom_len == 0) {
        rom_len = board.Info.mem.ram_len;
        rom_start_addr = board.Info.mem.ram_start_addr;
    } else {
        rom_len = board.Info.mem.rom_len + board.Info.mem.ram_len;
        rom_start_addr = board.Info.mem.rom_start_addr;
    }

    // MMU page dir config

    bprint("romlen: {d} \n", .{rom_len});
    // writing to _id_mapped_dir(label) page table and creating new
    // identity mapped memory for bootloader to kernel transfer
    const bootloader_mapping = mmu.Mapping{ .mem_size = rom_len, .virt_start_addr = 0, .phys_addr = rom_start_addr, .granule = Granule.Section, .flags = mmu.TableEntryAttr{ .accessPerm = .only_el1_read_write, .descType = .block } };
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

    // updating page dirs
    proc.setTTBR1(_ttbr1_dir);
    proc.setTTBR0(_ttbr0_dir);

    // t0sz: The size offset of the memory region addressed by TTBR0_EL1 (64-48=16)
    // t1sz: The size offset of the memory region addressed by TTBR1_EL1
    // tg0: Granule size for the TTBR0_EL1.
    // tg1 not required since it's sections
    proc.setTcrEl1((mmu.TcrReg{ .t0sz = 16, .t1sz = 16 }).asInt());
    proc.setMairEl1((mmu.MairReg{ .attr1 = 4, .attr2 = 4 }).asInt());

    proc.invalidateMmuTlbEl1();
    proc.invalidateCache();
    proc.isb();
    bprint("[bootloader] enabling mmu... \n", .{});
    proc.enableMmu();

    if (board.Info.mem.rom_len != 0) {
        bprint("[bootloader] setup mmu, el1, exc table. \n", .{});
        bprint("[bootloader] Copying kernel to secure: 0x{x}, with size: {d} \n", .{ @ptrToInt(kernel_target_loc.ptr), kernel_target_loc.len });
        std.mem.copy(u8, kernel_target_loc, kernel_bl);
        bprint("[bootloader] kernel copied \n", .{});
    }

    bprint("[bootloader] jumping to secure kernel \n", .{});
    if (board.Info.mem.rom_len == 0) {
        proc.branchToAddr(kernel_entry);
    } else {
        proc.branchToAddr(@ptrToInt(kernel_target_loc.ptr));
    }

    while (true) {}
}

comptime {
    @export(intHandle.irqHandler, .{ .name = "irqHandler", .linkage = .Strong });
    @export(intHandle.irqElxSpx, .{ .name = "irqElxSpx", .linkage = .Strong });
}
