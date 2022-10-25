const std = @import("std");
const arm = @import("arm");
const periph = @import("periph");
const utils = @import("utils");
const k_utils = @import("utils.zig");
const tests = @import("tests.zig");

// pre_kernel_page_table_init_kprint...
// uses userspace addresses(ttbr0), since those are still identity mapped
// to access peripherals
const pkpti_kprint = periph.uart.UartWriter(.ttbr0).kprint;

const kprint = periph.uart.UartWriter(.ttbr0).kprint;
const gic = arm.gicv2.Gic(.ttbr1);

// kernel services
const KernelAllocator = @import("KernelAllocator.zig").KernelAllocator;
// const UserPageAllocator = @import("UserPageAllocator.zig").UserPageAllocator;
const intHandle = @import("gicHandle.zig");
const b_options = @import("build_options");
const board = @import("board");

const proc = arm.processor.ProccessorRegMap(.ttbr1, .el1, false);
const mmu = arm.mmu;

// raspberry
const bcm2835IntController = arm.bcm2835IntController.InterruptController(.ttbr1);
const timer = arm.timer;

const kernel_bin_size = b_options.kernel_bin_size;
const bl_bin_size = b_options.bl_bin_size;

export fn kernel_main() callconv(.Naked) noreturn {
    // setting stack pointer to writable memory (ram (userspace))
    {
        const _stack_top: usize = @ptrToInt(@extern(?*u8, .{ .name = "_stack_bottom" }) orelse {
            kprint("error reading _stack_top label\n", .{});
            unreachable;
        });

        // setting stack back to linker section
        proc.setSp(_stack_top);
    }

    pkpti_kprint("[kernel] kernel started! \n", .{});

    // kernelspace allocator test
    var kspace_alloc = blk: {
        const _kernel_space_start: usize = @ptrToInt(@extern(?*u8, .{ .name = "_kernel_space_start" }) orelse {
            kprint("[panic] error reading _kernel_space_start label\n", .{});
            k_utils.panic();
        });
        // kprint("kss: {x} \n", .{_kernel_space_start});
        var kernel_alloc = KernelAllocator(board.config.mem.ram_layout.kernel_space_size - kernel_bin_size, 102400).init(_kernel_space_start) catch |e| {
            kprint("[panic] KernelAllocator init error: {s}\n", .{@errorName(e)});
            k_utils.panic();
        };
        break :blk kernel_alloc;
    };

    comptime var no_rom_bl_bin_offset = 0;
    if (!board.config.mem.has_rom) no_rom_bl_bin_offset = bl_bin_size;

    // mmu config block
    {
        const ttbr1 = blk: {
            comptime var ttbr1_size = board.boardConfig.calcPageTableSizeTotal(board.boardConfig.Granule.FourkSection, board.config.mem.ram_layout.kernel_space_size + 0x40000000 + board.PeriphConfig(.ttbr0).device_base_size) catch |e| {
                @compileError(@errorName(e));
            };

            // const _ttbr1: usize = @ptrToInt(@extern(?*u8, .{ .name = "_deprecated_ttbr1" }) orelse {
            //     kprint("[panic] error reading _ttbr1 label\n", .{});
            //     unreachable;
            // });
            // const ttbr1_arr = @intToPtr(*volatile [ttbr1_size]usize, _ttbr1);
            const ttbr1_arr = @ptrCast(*volatile [ttbr1_size]usize, (kspace_alloc.alloc(usize, ttbr1_size, 4096) catch |e| {
                kprint("[panic] Page table kalloc error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            }).ptr);
            // kprint("ttbr1 addr: {*} \n", .{&ttbr1_arr[0]});

            // creating virtual address space for kernel
            const kernel_space_mapping = mmu.Mapping{
                .mem_size = board.config.mem.ram_layout.kernel_space_size,
                .pointing_addr_start = board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0),
                .virt_addr_start = 0,
                .granule = board.config.mem.ram_layout.kernel_space_gran,
                .addr_space = .ttbr1,
                .flags_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .only_el1_read_write, .descType = .page, .attrIndex = .mair0 },
                .flags_non_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .only_el1_read_write, .descType = .page },
            };
            // mapping general kernel mem (inlcuding device base)
            var ttbr1_write = (mmu.PageTable(kernel_space_mapping) catch |e| {
                kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            }).init(ttbr1_arr, board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0) + no_rom_bl_bin_offset) catch |e| {
                kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            };
            ttbr1_write.mapMem() catch |e| {
                kprint("[panic] Page table write error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            };

            // creating virtual address space for kernel
            const periph_mapping = mmu.Mapping{
                .mem_size = board.PeriphConfig(.ttbr0).device_base_size,
                .pointing_addr_start = board.PeriphConfig(.ttbr0).device_base,
                .virt_addr_start = 0x40000000,
                .granule = board.config.mem.ram_layout.kernel_space_gran,
                .addr_space = .ttbr1,
                .flags_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .only_el1_read_write, .descType = .block, .attrIndex = .mair0 },
                .flags_non_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .only_el1_read_write, .descType = .page },
            };
            // mapping general kernel mem (inlcuding device base)
            var ttbr1_periph_write = (mmu.PageTable(periph_mapping) catch |e| {
                kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            }).init(ttbr1_arr, board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0)) catch |e| {
                kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            };
            ttbr1_periph_write.mapMem() catch |e| {
                kprint("[panic] Page table write error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            };

            break :blk ttbr1_arr;
        };

        // user space is runtime evalua
        const ttbr0 = blk: {
            comptime var ttbr0_size = (board.boardConfig.calcPageTableSizeTotal(board.config.mem.ram_layout.user_space_gran, board.config.mem.ram_layout.user_space_size) catch |e| {
                @compileError(@errorName(e));
            });

            // const _ttbr0: usize = @ptrToInt(@extern(?*u8, .{ .name = "_deprecated_ttbr0" }) orelse {
            //     kprint("error reading _ttbr0 label\n", .{});
            //     unreachable;
            // });
            // const ttbr0_arr = @intToPtr(*volatile [ttbr0_size]usize, _ttbr0);
            // _ = kspace_alloc;

            const ttbr0_arr = @ptrCast(*volatile [ttbr0_size]usize, (kspace_alloc.alloc(usize, ttbr0_size, 4096) catch |e| {
                kprint("[panic] Page table kalloc error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            }).ptr);
            // kprint("ttbr0 addr: {*} \n", .{&ttbr0_arr[0]});

            // MMU page dir config

            // writing to _id_mapped_dir(label) page table and creating new
            // identity mapped memory for bootloader to kernel transfer
            const user_space_mapping = mmu.Mapping{
                .mem_size = board.config.mem.ram_layout.user_space_size,
                .pointing_addr_start = (board.config.mem.rom_size orelse 0) + board.config.mem.ram_layout.kernel_space_size + board.config.mem.ram_layout.user_space_phys,
                .virt_addr_start = 0,
                .granule = board.config.mem.ram_layout.user_space_gran,
                .addr_space = .ttbr0,
                .flags_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .only_el1_read_write, .descType = .page, .attrIndex = .mair0 },
                .flags_non_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .only_el1_read_write, .descType = .page },
            };
            // identity mapped memory for bootloader and kernel contrtol handover!
            var ttbr0_write = (mmu.PageTable(user_space_mapping) catch |e| {
                kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            }).init(ttbr0_arr, board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0) + no_rom_bl_bin_offset) catch |e| {
                kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            };
            ttbr0_write.mapMem() catch |e| {
                kprint("[panic] Page table write error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            };
            break :blk ttbr0_arr;
        };

        // kprint("[kernel] changing to kernel page tables.. \n", .{});
        pkpti_kprint("0: {*} 1: {*} \n", .{ ttbr0, ttbr1 });
        // kprint("{any} \n", .{ttbr1.*});

        brfn();

        proc.TcrReg.setTcrEl(.el1, (proc.TcrReg{ .t0sz = 25, .t1sz = 25, .tg0 = 0, .tg1 = 0 }).asInt());
        proc.MairReg.setMairEl(.el1, (proc.MairReg{ .attr0 = 0xFF, .attr1 = 0x0, .attr2 = 0x0, .attr3 = 0x0, .attr4 = 0x0 }).asInt());

        proc.dsb();
        proc.isb();

        proc.invalidateOldPageTableEntries();

        // updating page dirs for kernel and user space
        // toUnse is bc we are in ttbr1 and can't change with page tables that are also in ttbr1
        kprint("addr: {x} \n", .{board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0) + no_rom_bl_bin_offset + mmu.toUnsecure(usize, @ptrToInt(ttbr1))});
        kprint("text {d} \n", .{mmu.toUnsecure(usize, @ptrToInt(ttbr1))});
        proc.setTTBR1(board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0) + no_rom_bl_bin_offset + mmu.toUnsecure(usize, @ptrToInt(ttbr1)));
        // proc.setTTBR0(board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0) + mmu.toUnsecure(usize, @ptrToInt(ttbr0)));
        _ = ttbr0;

        // proc.invalidateMmuTlbEl1();
        proc.invalidateCache();

        proc.dsb();
        proc.isb();
        proc.nop();
        proc.nop();
    }
    kprint("[kernel] page tables updated! \n", .{});

    var current_el = proc.getCurrentEl();
    if (current_el != 1) {
        kprint("[panic] el must be 1! (it is: {d})\n", .{current_el});
        proc.panic();
    }
    // if (board.config.board == .qemuVirt) {
    //     gic.init() catch |e| {
    //         kprint("[panic] Page table ttbr0 address calc error: {s}\n", .{@errorName(e)});
    //         k_utils.panic();
    //     };
    // }
    // if (board.config.board == .raspi3b) {
    //     timer.initTimer();
    //     kprint("[kernel] timer inited \n", .{});

    //     bcm2835IntController.init();
    //     kprint("[kernel] ic inited \n", .{});
    // }

    kprint("[kernel] kernel boot complete \n", .{});

    // // userspace page allocator test
    // {
    //     var page_alloc_start = utils.ceilRoundToMultiple((board.config.mem.rom_size orelse 0) + board.config.mem.ram_layout.kernel_space_size, board.config.mem.ram_layout.user_space_gran.page_size) catch |e| {
    //         kprint("[panic] UserSpaceAllocator start addr calc err: {s}\n", .{@errorName(e)});
    //         k_utils.panic();
    //     };

    //     var user_page_alloc = (UserPageAllocator(204800, board.config.mem.ram_layout.user_space_gran) catch |e| {
    //         kprint("[panic] UserSpaceAllocator init error: {s} \n", .{@errorName(e)});
    //         k_utils.panic();
    //     }).init(page_alloc_start) catch |e| {
    //         kprint("[panic] UserSpaceAllocator init error: {s} \n", .{@errorName(e)});
    //         k_utils.panic();
    //     };
    //     tests.testUserPageAlloc(&user_page_alloc) catch |e| {
    //         kprint("[panic] UserSpaceAllocator test error: {s} \n", .{@errorName(e)});
    //         k_utils.panic();
    //     };
    // }

    // kernel alloc test
    {
        tests.testKMalloc(&kspace_alloc) catch |e| {
            kprint("[panic] KMalloc test error: {s} \n", .{@errorName(e)});
            k_utils.panic();
        };
    }

    kprint("tests complete \n", .{});

    // if (board.config.board == .raspi3b)
    //     tests.testUserSpaceMem(100);

    // if (board.config.board == .qemuVirt)
    //     tests.testUserSpaceMem(100);

    while (true) {}
}

pub fn brfn() void {
    kprint("[kernel] gdb breakpoint function... \n", .{});
}

comptime {
    @export(intHandle.irqHandler, .{ .name = "irqHandler", .linkage = .Strong });
    @export(intHandle.irqElxSpx, .{ .name = "irqElxSpx", .linkage = .Strong });
}
