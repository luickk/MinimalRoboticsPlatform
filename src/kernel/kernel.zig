const std = @import("std");
const arm = @import("arm");
const periph = @import("periph");
const utils = @import("utils");
const k_utils = @import("utils.zig");
const tests = @import("tests.zig");

const kprint = periph.uart.UartWriter(.ttbr1).kprint;
const gic = arm.gicv2.Gic(.ttbr1);

// kernel services
const KernelAllocator = @import("KernelAllocator.zig").KernelAllocator;
const UserPageAllocator = @import("UserPageAllocator.zig").UserPageAllocator;
const intHandle = @import("gicHandle.zig");
const b_options = @import("build_options");
const board = @import("board");

const proc = arm.processor.ProccessorRegMap(.ttbr1, .el1, false);
const mmu = arm.mmu;

// raspberry
const bcm2835IntController = arm.bcm2835IntController.InterruptController(.ttbr1);
const timer = arm.timer;

const ttbr1 align(4096) = blk: {
    @setEvalBranchQuota(1000000);

    // ttbr0 (rom) mapps both rom and ram
    // todo => !! fix should be -> board.config.mem.ram_layout.kernel_space_size !! (this is due to phys_addr (mapping with offset) not working...)
    const ttbr1_size = (board.boardConfig.calcPageTableSizeTotal(board.boardConfig.Granule.Section, board.config.mem.ram_size + (board.config.mem.rom_size orelse 0)) catch |e| {
        @compileError(@errorName(e));
    });
    var ttbr1_arr: [ttbr1_size]usize align(4096) = [_]usize{0} ** ttbr1_size;

    // creating virtual address space for kernel
    const kernel_space_mapping = mmu.Mapping{
        // todo => !! fix should be -> board.config.mem.ram_layout.kernel_space_size !! (this is due to phys_addr (mapping with offset) not working...)
        .mem_size = board.config.mem.ram_size + (board.config.mem.rom_size orelse 0),
        .phys_addr = (board.config.mem.rom_size orelse 0) + board.config.mem.ram_layout.kernel_space_phys,
        .granule = board.config.mem.ram_layout.kernel_space_gran,
        .flags = mmu.TableDescriptorAttr{ .accessPerm = .only_el1_read_write, .descType = .block },
    };
    // mapping general kernel mem (inlcuding device base)
    var ttbr1_write = (mmu.PageTable(kernel_space_mapping) catch |e| {
        @compileError(@errorName(e));
    }).init(&ttbr1_arr) catch |e| {
        @compileError(@errorName(e));
    };
    ttbr1_write.mapMem() catch |e| {
        @compileError(@errorName(e));
    };
    break :blk ttbr1_arr;
};

export fn kernel_main() callconv(.Naked) noreturn {
    const _stack_top: usize = @ptrToInt(@extern(?*u8, .{ .name = "_stack_top" }) orelse {
        kprint("error reading _stack_top label\n", .{});
        unreachable;
    });

    // setting stack back to linker section
    proc.setSp(mmu.toSecure(usize, _stack_top));

    kprint("[kernel] kernel started! \n", .{});
    kprint("[kernel] configuring mmu... \n", .{});

    const _kernel_ttbr0: usize = @ptrToInt(@extern(?*u8, .{ .name = "_kernel_ttbr0" }) orelse {
        kprint("error reading _kernel_ttbr0 label\n", .{});
        unreachable;
    });

    // mmu config block
    {
        kprint("ttbr0: {x} \n", .{_kernel_ttbr0});
        kprint("ttbr1: {x} \n", .{@ptrToInt(&ttbr1)});
        // user space is runtime evalua
        const ttbr0 = blk: {
            // ttbr0 (rom) mapps both rom and ram
            // todo => !! fix should be -> board.config.mem.ram_layout.kernel_space_size !! (this is due to phys_addr (mapping with offset) not working...)
            comptime var ttbr0_size = (board.boardConfig.calcPageTableSizeTotal(board.config.mem.ram_layout.user_space_gran, board.config.mem.ram_size + (board.config.mem.rom_size orelse 0)) catch |e| {
                kprint("[panic] Page table size calc error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            });

            // todo => write proper kernel allocater and put it there
            const ttbr0_arr = @intToPtr(*[ttbr0_size]usize, _kernel_ttbr0);

            // MMU page dir config

            // writing to _id_mapped_dir(label) page table and creating new
            // identity mapped memory for bootloader to kernel transfer
            const user_space_mapping = mmu.Mapping{
                // todo => !! fix should be -> board.config.mem.ram_layout.kernel_space_size !! (this is due to phys_addr (mapping with offset) not working...)
                .mem_size = board.config.mem.ram_size + (board.config.mem.rom_size orelse 0),
                .phys_addr = (board.config.mem.rom_size orelse 0) + board.config.mem.ram_layout.kernel_space_size + board.config.mem.ram_layout.user_space_phys,
                .granule = board.config.mem.ram_layout.user_space_gran,
                .flags = mmu.TableDescriptorAttr{ .accessPerm = .only_el1_read_write, .descType = .block },
            };
            // identity mapped memory for bootloader and kernel contrtol handover!
            var ttbr0_write = (mmu.PageTable(user_space_mapping) catch |e| {
                kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            }).init(ttbr0_arr) catch |e| {
                kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            };
            ttbr0_write.mapMem() catch |e| {
                kprint("[panic] Page table write error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            };
            break :blk ttbr0_arr;
        };
        kprint("[kernel] changing to kernel page tables.. \n", .{});
        // t0sz: The size offset of the memory region addressed by TTBR0_EL1 (64-48=16)
        // t1sz: The size offset of the memory region addressed by TTBR1_EL1
        // tg0: Granule size for the TTBR0_EL1.
        proc.TcrReg.setTcrEl(.el1, (proc.TcrReg{ .t0sz = 16, .t1sz = 16, .tg0 = 0 }).asInt());
        proc.MairReg.setMairEl(.el1, (proc.MairReg{ .attr0 = 4, .attr1 = 0x0, .attr2 = 0x0, .attr3 = 0x0, .attr4 = 0x0 }).asInt());

        proc.dsb();
        proc.isb();

        // updating page dirs for kernel and user space
        // toUnse is bc we are in ttbr1 and can't change with page tables that are also in ttbr1
        proc.setTTBR1(@ptrToInt(&ttbr1));
        proc.setTTBR0(@ptrToInt(ttbr0));

        proc.invalidateMmuTlbEl1();
        proc.invalidateCache();

        proc.dsb();
        proc.isb();
    }

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

    kprint("[kernel] kernel boot complete \n", .{});

    // var page_alloc_start = utils.ceilRoundToMultiple(_kernel_ttbr0, 8) catch |e| {
    //     kprint("[panic] UserSpaceAllocator start addr calc err: {s}\n", .{@errorName(e)});
    //     k_utils.panic();
    // };

    // var user_page_alloc = (UserPageAllocator(204800, board.config.mem.ram_layout.user_space_gran) catch |e| {
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
        tests.testUserSpaceMem(100);

    if (board.config.board == .qemuVirt)
        tests.testUserSpaceMem(100);

    while (true) {}
}

pub fn brfn() void {
    kprint("[kernel] gdb breakpoint function... \n", .{});
}

comptime {
    @export(intHandle.irqHandler, .{ .name = "irqHandler", .linkage = .Strong });
    @export(intHandle.irqElxSpx, .{ .name = "irqElxSpx", .linkage = .Strong });
}
