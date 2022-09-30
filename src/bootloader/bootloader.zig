const std = @import("std");
const bl_utils = @import("utils.zig");
const utils = @import("utils");
const intHandle = @import("gicHandle.zig");
const arm = @import("arm");
const periph = @import("periph");
const board = @import("board");
const b_options = @import("build_options");
const proc = arm.processor;
const mmuComp = arm.mmuComptime;
const mmu = arm.mmu;
// bool arg sets the addresses value to either mmu kernel_space or unsecure
const PeriphConfig = board.PeriphConfig(false);
const pl011 = periph.Pl011(false);
const kprint = periph.uart.UartWriter(false).kprint;

// raspberry
const bcm2835IntController = arm.bcm2835IntController.InterruptController(false);

const gic = arm.gicv2.Gic(false);

const Granule = board.boardConfig.Granule;
const GranuleParams = board.boardConfig.GranuleParams;
const TransLvl = board.boardConfig.TransLvl;

const kernel_bin_size = b_options.kernel_bin_size;

// todo => ttbr1 for kernel is ranging from 0x0-1g instead of _ramSize_ + _bl_load_addr-1g!. Alternatively link kernel with additional offset

// note: when bl_main gets too bit(instruction mem wise), the exception vector table could be pushed too far up and potentially not be read!
export fn bl_main() callconv(.Naked) noreturn {
    // using userspace as stack, incase the bootloader is located in rom
    proc.setSp(board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0) + board.config.mem.ram_layout.kernel_space_size + board.config.mem.bl_stack_size);

    if (board.config.board == .raspi3b)
        bcm2835IntController.init();

    // GIC Init
    if (board.config.board == .qemuVirt) {
        gic.init() catch |e| {
            kprint("[panic] GIC init error: {s} \n", .{@errorName(e)});
            bl_utils.panic();
        };
        pl011.init();
    }

    // proc.exceptionSvc();

    // get address of external linker script variable which marks stack-top and kernel start
    const kernel_entry: usize = @ptrToInt(@extern(?*u8, .{ .name = "_kernelrom_start", .linkage = .Strong }) orelse {
        kprint("error reading _kernelrom_start label\n", .{});
        bl_utils.panic();
    });

    var kernel_bl: []u8 = undefined;
    kernel_bl.ptr = @intToPtr([*]u8, kernel_entry);
    kernel_bl.len = kernel_bin_size;

    var kernel_target_loc: []u8 = undefined;
    kernel_target_loc.ptr = @intToPtr([*]u8, mmu.toSecure(usize, board.config.mem.ram_start_addr));
    kernel_target_loc.len = kernel_bin_size;

    var current_el = proc.getCurrentEl();
    if (current_el != 1) {
        kprint("[panic] el must be 1! (it is: {d})\n", .{current_el});
        bl_utils.panic();
    }

    // writing page dirs to userspace in ram. Writing to userspace because it would be overwritten in kernel space, when copying
    // the kernel. Additionally, on mmu turn on, the mmu would try to read from the page tables without mmu kernel space identifier bits on
    // todo => make page dir generation comptime generated and static memory! (currently prevented by max array-size)
    const user_space_start = board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0) + board.config.mem.ram_layout.kernel_space_size + board.config.mem.bl_stack_size;
    var _ttbr1_dir = user_space_start;
    var _ttbr0_dir = user_space_start + (board.config.mem.calcPageTableSizeRam(board.boardConfig.Granule.Fourk) catch |e| {
        kprint("[panic] Page table ttbr0 address calc error: {s}\n", .{@errorName(e)});
        bl_utils.panic();
    });

    _ttbr0_dir = utils.ceilRoundToMultiple(_ttbr0_dir, Granule.Section.page_size) catch |e| {
        kprint("[panic] Page table ttbr0 address calc error: {s}\n", .{@errorName(e)});
        bl_utils.panic();
    };
    _ttbr1_dir = utils.ceilRoundToMultiple(_ttbr1_dir, Granule.Section.page_size) catch |e| {
        kprint("[panic] Page table ttbr0 address calc error: {s}\n", .{@errorName(e)});
        bl_utils.panic();
    };

    // in case there is no rom(rom_size is equal to zero) and the kernel(and bl) are directly loaded to memory by some rom bootloader
    // the ttbr0 memory is also identity mapped to the ram
    comptime var rom_size: usize = undefined;
    comptime var rom_start_addr: usize = undefined;
    if (board.config.mem.rom_start_addr == null) {
        rom_size = board.config.mem.ram_size;
        rom_start_addr = board.config.mem.ram_start_addr;
    } else {
        rom_size = (board.config.mem.rom_size orelse 0) + board.config.mem.ram_size;
        rom_start_addr = board.config.mem.rom_start_addr orelse 0;
    }

    // MMU page dir config

    // writing to _id_mapped_dir(label) page table and creating new
    // identity mapped memory for bootloader to kernel transfer
    const bootloader_mapping = mmu.Mapping{
        .mem_size = rom_size,
        .virt_start_addr = 0,
        .phys_addr = rom_start_addr,
        .granule = Granule.Section,
        .flags = mmu.TableEntryAttr{ .accessPerm = .only_el1_read_write, .descType = .block },
    };
    // identity mapped memory for bootloader and kernel contrtol handover!
    var ttbr0 = (mmu.PageDir(bootloader_mapping) catch |e| {
        @compileError(@errorName(e));
    }).init(_ttbr0_dir) catch |e| {
        kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
        bl_utils.panic();
    };
    ttbr0.mapMem() catch |e| {
        kprint("[panic] memory mapping error: {s} \n", .{@errorName(e)});
        bl_utils.panic();
    };

    const kernel_mapping = mmu.Mapping{
        .mem_size = board.config.mem.ram_size,
        .virt_start_addr = board.config.mem.va_start,
        .phys_addr = board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0),
        .granule = Granule.Section,
        .flags = mmu.TableEntryAttr{ .accessPerm = .only_el1_read_write, .descType = .block },
    };

    // mapping general kernel mem (inlcuding device base)
    var ttbr1 = (mmu.PageDir(kernel_mapping) catch |e| {
        @compileError(@errorName(e));
    }).init(_ttbr1_dir) catch |e| {
        kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
        bl_utils.panic();
    };
    ttbr1.mapMem() catch |e| {
        kprint("[panic] memory mapping error: {s} \n", .{@errorName(e)});
        bl_utils.panic();
    };

    // // MMU page dir config

    // kprint("addr: 0x{x} \n", .{_ttbr1_dir});

    // updating page dirs
    proc.setTTBR1(_ttbr1_dir);
    proc.setTTBR0(_ttbr0_dir);

    // t0sz: The size offset of the memory region addressed by TTBR0_EL1 (64-48=16)
    // t1sz: The size offset of the memory region addressed by TTBR1_EL1
    // tg0: Granule size for the TTBR0_EL1.
    // tg1 not required since it's sections
    proc.setTcrEl1((mmu.TcrReg{ .t0sz = 16, .t1sz = 16, .tg1 = 2 }).asInt());

    proc.invalidateMmuTlbEl1();
    proc.invalidateCache();
    proc.isb();
    kprint("[bootloader] enabling mmu... \n", .{});
    proc.enableMmu();

    if (board.config.mem.rom_start_addr != null) {
        kprint("[bootloader] setup mmu, el1, exc table. \n", .{});
        kprint("[bootloader] Copying kernel to kernel_space: 0x{x}, with size: {d} \n", .{ @ptrToInt(kernel_target_loc.ptr), kernel_target_loc.len });
        std.mem.copy(u8, kernel_target_loc, kernel_bl);
        kprint("[bootloader] kernel copied \n", .{});
    }
    var kernel_addr = @ptrToInt(kernel_target_loc.ptr);
    if (board.config.mem.rom_start_addr == null)
        kernel_addr = mmu.toSecure(usize, kernel_entry);

    kprint("[bootloader] jumping to kernel_space kernel at 0x{x}\n", .{kernel_addr});

    proc.branchToAddr(kernel_addr);

    while (true) {}
}

comptime {
    @export(intHandle.irqHandler, .{ .name = "irqHandler", .linkage = .Strong });
    @export(intHandle.irqElxSpx, .{ .name = "irqElxSpx", .linkage = .Strong });
}
