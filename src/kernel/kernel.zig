const std = @import("std");
const arm = @import("arm");
const periph = @import("periph");
const utils = @import("utils");
const k_utils = @import("utils.zig");
const tests = @import("tests.zig");

const kprint = periph.uart.UartWriter(true).kprint;
const gic = arm.gicv2.Gic(true);

// kernel services
const UserSpaceAllocator = @import("memory.zig").UserSpaceAllocator;
const intHandle = @import("gicHandle.zig");
const b_options = @import("build_options");
const board = @import("board");

const proc = arm.processor;
const mmu = arm.mmu;
const mmuComp = arm.mmuComptime;

// raspberry
const bcm2835IntController = arm.bcm2835IntController.InterruptController(true);
const timer = arm.timer;

const ttbr1 align(4096) = blk: {
    @setEvalBranchQuota(1000000);

    // ttbr0 (rom) mapps both rom and ram
    const ttbr1_size = (board.boardConfig.calcPageTableSizeTotal(board.boardConfig.Granule.Section, board.config.mem.ram_layout.kernel_space_size, 4096) catch |e| {
        @compileError(@errorName(e));
    });
    var ttbr1_arr: [ttbr1_size]usize align(4096) = [_]usize{0} ** ttbr1_size;

    // creating virtual address space for kernel
    const kernel_space_mapping = mmuComp.Mapping{
        .mem_size = board.config.mem.ram_layout.kernel_space_size,
        .virt_start_addr = board.config.mem.ram_layout.kernel_space_vs,
        .phys_addr = (board.config.mem.rom_size orelse 0) + board.config.mem.ram_layout.kernel_space_phys,
        .granule = board.config.mem.ram_layout.kernel_space_gran,
        .flags = mmuComp.TableDescriptorAttr{ .accessPerm = .only_el1_read_write, .descType = .block },
    };
    // mapping general kernel mem (inlcuding device base)
    var ttbr1_write = (mmuComp.PageTable(kernel_space_mapping) catch |e| {
        @compileError(@errorName(e));
    }).init(&ttbr1_arr) catch |e| {
        @compileError(@errorName(e));
    };
    ttbr1_write.mapMem() catch |e| {
        @compileError(@errorName(e));
    };
    break :blk ttbr1_arr;
};

const ttbr0 align(4096) = blk: {
    @setEvalBranchQuota(1000000);

    // ttbr0 (rom) mapps both rom and ram
    const ttbr0_size = (board.boardConfig.calcPageTableSizeTotal(board.boardConfig.Granule.Fourk, board.config.mem.ram_layout.user_space_size, 4096) catch |e| {
        @compileError(@errorName(e));
    });

    var ttbr0_arr: [ttbr0_size]usize align(4096) = [_]usize{0} ** ttbr0_size;

    // MMU page dir config

    // writing to _id_mapped_dir(label) page table and creating new
    // identity mapped memory for bootloader to kernel transfer
    const user_space_mapping = mmuComp.Mapping{
        .mem_size = board.config.mem.ram_layout.user_space_size,
        .virt_start_addr = board.config.mem.ram_layout.user_space_vs,
        .phys_addr = (board.config.mem.rom_size orelse 0) + board.config.mem.ram_layout.kernel_space_size + board.config.mem.ram_layout.user_space_phys,
        .granule = board.config.mem.ram_layout.user_space_gran,
        .flags = null,
    };
    // identity mapped memory for bootloader and kernel contrtol handover!
    var ttbr0_write = (mmuComp.PageTable(user_space_mapping) catch |e| {
        @compileError(@errorName(e));
    }).init(&ttbr0_arr) catch |e| {
        @compileError(@errorName(e));
    };
    ttbr0_write.mapMem() catch |e| {
        @compileError(@errorName(e));
    };

    break :blk ttbr0_arr;
};

export fn kernel_main() callconv(.Naked) noreturn {
    kprint("[kernel] kernel started! \n", .{});

    const _kernel_end: usize = @ptrToInt(@extern(?*u8, .{ .name = "_stack_top" }) orelse {
        kprint("error reading _stack_top label\n", .{});
        unreachable;
    });

    var current_el = proc.getCurrentEl();
    if (current_el != 1) {
        kprint("[panic] el must be 1! (it is: {d})\n", .{current_el});
        proc.panic();
    }
    if (board.config.board == .qemuVirt) {
        gic.init() catch |e| {
            kprint("[panic] Page table ttbr0 address calc error: {s}\n", .{@errorName(e)});
            k_utils.panic();
        };
    }
    if (board.config.board == .raspi3b) {
        timer.initTimer();
        kprint("[kernel] timer inited \n", .{});

        bcm2835IntController.init();
        kprint("[kernel] ic inited \n", .{});
    }

    // t0sz: The size offset of the memory region addressed by TTBR0_EL1 (64-48=16)
    // t1sz: The size offset of the memory region addressed by TTBR1_EL1
    // tg0: Granule size for the TTBR0_EL1.
    proc.setTcrEl1((mmu.TcrReg{ .t0sz = 16, .t1sz = 16, .tg0 = 2 }).asInt());
    proc.setMairEl1((mmu.MairReg{ .attr0 = 0x00, .attr1 = 0x04, .attr2 = 0x0c, .attr3 = 0x44, .attr4 = 0xFF }).asInt());
    // // updating page dirs for kernel and user space
    // proc.setTTBR1(0x0);
    // proc.setTTBR0(0x0);
    // proc.dsb();
    // proc.isb();

    proc.invalidateMmuTlbEl1();
    proc.invalidateCache();

    proc.dsb();
    proc.isb();

    // updating page dirs for kernel and user space
    proc.setTTBR1(@ptrToInt(&ttbr1));
    proc.setTTBR0(@ptrToInt(&ttbr0));

    proc.dsb();
    proc.isb();

    kprint("[kernel] kernel boot complete \n", .{});

    _ = _kernel_end;
    // var page_alloc_start = utils.ceilRoundToMultiple(_kernel_end, board.config.mem.ram_layout.user_space_gran.page_size) catch |e| {
    //     kprint("[panic] UserSpaceAllocator start addr calc err: {s}\n", .{@errorName(e)});
    //     k_utils.panic();
    // };
    // var user_page_alloc = (UserSpaceAllocator(204800, board.config.mem.ram_layout.user_space_gran) catch |e| {
    //     kprint("[panic] UserSpaceAllocator init error: {s} \n", .{@errorName(e)});
    //     k_utils.panic();
    // }).init(page_alloc_start) catch |e| {
    //     kprint("[panic] UserSpaceAllocator init error: {s} \n", .{@errorName(e)});
    //     k_utils.panic();
    // };

    // tests.testKMalloc(&user_page_alloc) catch |e| {
    //     kprint("[panic] UserSpaceAllocator test error: {s} \n", .{@errorName(e)});
    //     k_utils.panic();
    // };
    if (board.config.board == .raspi3b)
        tests.testUserSpaceMem(0x30000000);

    if (board.config.board == .qemuVirt)
        tests.testUserSpaceMem(0x60000000);

    while (true) {}
}

comptime {
    @export(intHandle.irqHandler, .{ .name = "irqHandler", .linkage = .Strong });
    @export(intHandle.irqElxSpx, .{ .name = "irqElxSpx", .linkage = .Strong });
}
