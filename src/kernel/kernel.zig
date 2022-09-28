const std = @import("std");
const arm = @import("arm");
const utils = @import("utils");
const k_utils = @import("utils.zig");
const tests = @import("tests.zig");

const kprint = arm.uart.UartWriter(true).kprint;
// kernel services
const UserSpaceAllocator = @import("memory.zig").UserSpaceAllocator;
const intHandle = @import("gicHandle.zig");
const b_options = @import("build_options");
const board = @import("board");

const proc = arm.processor;
const mmu = arm.mmu;

// raspberry
const bcm2835IntController = arm.bcm2835IntController.InterruptController(true);
const timer = arm.timer;

export fn kernel_main() callconv(.Naked) noreturn {
    kprint("[kernel] kernel started! \n", .{});

    const _k_ttbr1_dir: usize = @ptrToInt(@extern(?*u8, .{ .name = "_kernel_ttbr1_dir" }) orelse {
        kprint("error reading _kernel_ttbr1_dir label\n", .{});
        unreachable;
    });
    const _u_ttbr0_dir: usize = @ptrToInt(@extern(?*u8, .{ .name = "_user_ttbr0_dir" }) orelse {
        kprint("error reading _user_ttbr0_dir label\n", .{});
        unreachable;
    });

    const _kernel_end: usize = @ptrToInt(@extern(?*u8, .{ .name = "_stack_top" }) orelse {
        kprint("error reading _stack_top label\n", .{});
        unreachable;
    });

    _ = _kernel_end;
    // todo => reduce kernel bin size by not accounting for page tables
    // if (mmu.toUnsecure(usize, _kernel_end) > board.config.mem.ram_size) {
    //     kprint("[panic] kernel exceeding ram mem (0x{x})\n", .{mmu.toUnsecure(usize, _kernel_end)});
    //     k_utils.panic();
    // }

    var current_el = proc.getCurrentEl();
    if (current_el != 1) {
        kprint("[panic] el must be 1! (it is: {d})\n", .{current_el});
        proc.panic();
    }

    if (board.config.board == .raspi3b) {
        timer.initTimer();
        kprint("[kernel] timer inited \n", .{});

        bcm2835IntController.init();
        kprint("[kernel] ic inited \n", .{});
    }

    const kernel_space_mapping = mmu.Mapping{
        .mem_size = board.config.mem.ram_layout.kernel_space_size,
        .virt_start_addr = board.config.mem.ram_layout.kernel_space_vs,
        .phys_addr = (board.config.mem.rom_size orelse 0) + board.config.mem.ram_layout.kernel_space_phys,
        .granule = board.config.mem.ram_layout.kernel_space_gran,
        .flags = mmu.TableEntryAttr{ .accessPerm = .only_el1_read_write, .descType = .block },
    };

    // creating virtual address space for kernel
    var ttbr1 = (mmu.PageDir(kernel_space_mapping) catch |e| {
        @compileError(@errorName(e));
    }).init(_k_ttbr1_dir) catch |e| {
        kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
        k_utils.panic();
    };
    ttbr1.mapMem() catch |e| {
        kprint("[panic] memory mapping error: {s} \n", .{@errorName(e)});
        k_utils.panic();
    };

    const user_space_mapping = mmu.Mapping{
        .mem_size = board.config.mem.ram_layout.user_space_size,
        .virt_start_addr = board.config.mem.ram_layout.user_space_vs,
        .phys_addr = (board.config.mem.rom_size orelse 0) + board.config.mem.ram_layout.kernel_space_size + board.config.mem.ram_layout.user_space_phys,
        .granule = board.config.mem.ram_layout.user_space_gran,
        .flags = null,
    };

    // creating virtual address space user space with 4096 granule
    var ttbr0 = (mmu.PageDir(user_space_mapping) catch |e| {
        @compileError(@errorName(e));
    }).init(_u_ttbr0_dir) catch |e| {
        kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
        k_utils.panic();
    };
    ttbr0.mapMem() catch |e| {
        kprint("[panic] memory mapping error: {s} \n", .{@errorName(e)});
        k_utils.panic();
    };

    // t0sz: The size offset of the memory region addressed by TTBR0_EL1 (64-48=16)
    // t1sz: The size offset of the memory region addressed by TTBR1_EL1
    // tg0: Granule size for the TTBR0_EL1.
    proc.setTcrEl1((mmu.TcrReg{ .t0sz = 16, .t1sz = 16, .tg0 = 2 }).asInt());
    proc.invalidateMmuTlbEl1();
    proc.invalidateCache();
    // updating page dirs for kernel and user space
    proc.setTTBR1(_k_ttbr1_dir);
    proc.setTTBR0(_u_ttbr0_dir);

    kprint("[kernel] kernel boot complete \n", .{});
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
    tests.testUserSpaceMem();

    while (true) {}
}

comptime {
    @export(intHandle.irqHandler, .{ .name = "irqHandler", .linkage = .Strong });
    @export(intHandle.irqElxSpx, .{ .name = "irqElxSpx", .linkage = .Strong });
}
