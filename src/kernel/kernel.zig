const std = @import("std");
const arm = @import("arm");
const periph = @import("periph");
const utils = @import("utils");
const k_utils = @import("utils.zig");
const tests = @import("tests.zig");
const Scheduler = @import("Scheduler.zig").Scheduler;

const iD = @import("issueDemo.zig");

// pre_kernel_page_table_init_kprint...
// uses userspace addresses(ttbr0), since those are still identity mapped
// to access peripherals
const old_mapping_kprint = periph.uart.UartWriter(.ttbr0).kprint;

const kprint = periph.uart.UartWriter(.ttbr1).kprint;
const gic = arm.gicv2.Gic(.ttbr1);

// kernel services
const KernelAllocator = @import("KernelAllocator.zig").KernelAllocator;
const UserPageAllocator = @import("UserPageAllocator.zig").UserPageAllocator;
const intHandle = @import("gicHandle.zig");
const b_options = @import("build_options");
const board = @import("board");

const proc = arm.processor.ProccessorRegMap(.el1);
const mmu = arm.mmu;

// raspberry
const bcm2835IntController = arm.bcm2835IntController.InterruptController(.ttbr1);
const timer = arm.timer;

const kernel_bin_size = b_options.kernel_bin_size;
const bl_bin_size = b_options.bl_bin_size;

export fn kernel_main() linksection(".text.kernel_main") callconv(.Naked) noreturn {

    // if there is rom, the bootloader binary has to be taken into account for the offset
    comptime var no_rom_bl_bin_offset = 0;
    if (!board.config.mem.has_rom) no_rom_bl_bin_offset = bl_bin_size;
    {
        // setting stack pointer back to kernel stack linker region
        const _stack_top: usize = @ptrToInt(@extern(?*u8, .{ .name = "_stack_bottom" }) orelse {
            old_mapping_kprint("error reading _stack_top label\n", .{});
            k_utils.panic();
        });

        // const phys_offset_to_kernel = board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0) + no_rom_bl_bin_offset;
        // setting stack back to linker section
        proc.setSp(_stack_top);
    }

    // kernelspace allocator test
    var kspace_alloc = blk: {
        const _kernel_space_start: usize = @ptrToInt(@extern(?*u8, .{ .name = "_kernel_space_start" }) orelse {
            old_mapping_kprint("[panic] error reading _kernel_space_start label\n", .{});
            k_utils.panic();
        });
        // todo => for some reason this var is optimized away, if not printed (or somehow used explicitely)
        old_mapping_kprint("_kernel_space_start: {x} \n", .{_kernel_space_start});

        var kernel_alloc = KernelAllocator(board.config.mem.kernel_space_size - kernel_bin_size, 0x100000).init(_kernel_space_start) catch |e| {
            old_mapping_kprint("[panic] KernelAllocator init error: {s}\n", .{@errorName(e)});
            k_utils.panic();
        };
        break :blk kernel_alloc;
    };

    // mmu config block
    {
        const ttbr1 = blk: {
            var ttbr1_arr = blk_arr: {
                comptime var ttbr1_size = board.boardConfig.calcPageTableSizeTotal(board.config.mem.va_layout.va_kernel_space_gran, board.config.mem.va_layout.va_kernel_space_size) catch |e| {
                    @compileError(@errorName(e));
                };
                break :blk_arr @ptrCast(*volatile [ttbr1_size]usize, (kspace_alloc.alloc(usize, ttbr1_size, board.config.mem.va_layout.va_kernel_space_gran.page_size) catch |e| {
                    old_mapping_kprint("[panic] Page table kalloc error: {s}\n", .{@errorName(e)});
                    k_utils.panic();
                }).ptr);
            };

            // mapping general kernel mem (inlcuding device base)
            var ttbr1_write = (mmu.PageTable(board.config.mem.va_layout.va_kernel_space_size, board.config.mem.va_layout.va_kernel_space_gran) catch |e| {
                old_mapping_kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            }).init(ttbr1_arr, board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0) + no_rom_bl_bin_offset) catch |e| {
                old_mapping_kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            };

            {
                // creating virtual address space for kernel
                const kernel_space_mapping = mmu.Mapping{
                    .mem_size = board.config.mem.kernel_space_size,
                    .pointing_addr_start = board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0) + no_rom_bl_bin_offset,
                    .virt_addr_start = 0,
                    .granule = board.config.mem.va_layout.va_kernel_space_gran,
                    .addr_space = .ttbr1,
                    .flags_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .only_el1_read_write, .attrIndex = .mair0 },
                    .flags_non_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .only_el1_read_write },
                };
                ttbr1_write.mapMem(kernel_space_mapping) catch |e| {
                    old_mapping_kprint("[panic] Page table write error: {s}\n", .{@errorName(e)});
                    k_utils.panic();
                };
            }

            {
                // creating virtual address space for kernel
                const periph_mapping = mmu.Mapping{
                    .mem_size = board.PeriphConfig(.ttbr0).device_base_size,
                    .pointing_addr_start = board.PeriphConfig(.ttbr0).device_base,
                    .virt_addr_start = board.PeriphConfig(.ttbr0).new_ttbr1_device_base,
                    .granule = board.config.mem.va_layout.va_kernel_space_gran,
                    .addr_space = .ttbr1,
                    .flags_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .only_el1_read_write, .attrIndex = .mair0 },
                    .flags_non_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .only_el1_read_write },
                };

                ttbr1_write.mapMem(periph_mapping) catch |e| {
                    old_mapping_kprint("[panic] Page table write error: {s}\n", .{@errorName(e)});
                    k_utils.panic();
                };
            }

            break :blk ttbr1_arr;
        };

        const ttbr0 = blk: {
            const ttbr0_arr = blk_arr: {
                comptime var ttbr0_size = (board.boardConfig.calcPageTableSizeTotal(board.config.mem.va_layout.va_user_space_gran, board.config.mem.va_layout.va_user_space_size) catch |e| {
                    @compileError(@errorName(e));
                });

                break :blk_arr @ptrCast(*volatile [ttbr0_size]usize, (kspace_alloc.alloc(usize, ttbr0_size, 4096) catch |e| {
                    old_mapping_kprint("[panic] sPage table kalloc error: {s}\n", .{@errorName(e)});
                    k_utils.panic();
                }).ptr);
            };

            // MMU page dir config
            var ttbr0_write = (mmu.PageTable(board.config.mem.va_layout.va_user_space_size, board.config.mem.va_layout.va_user_space_gran) catch |e| {
                old_mapping_kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            }).init(ttbr0_arr, board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0) + no_rom_bl_bin_offset) catch |e| {
                old_mapping_kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            };

            const user_space_mapping = mmu.Mapping{
                .mem_size = board.config.mem.user_space_size,
                .pointing_addr_start = board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0) + no_rom_bl_bin_offset + board.config.mem.kernel_space_size,
                .virt_addr_start = 0,
                .granule = board.config.mem.va_layout.va_user_space_gran,
                .addr_space = .ttbr0,
                .flags_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .only_el1_read_write, .attrIndex = .mair0 },
                .flags_non_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .only_el1_read_write },
            };
            ttbr0_write.mapMem(user_space_mapping) catch |e| {
                old_mapping_kprint("[panic] Page table write error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            };
            break :blk ttbr0_arr;
        };

        // old_mapping_kprint("[kernel] changing to kernel page tables.. \n", .{});
        // old_mapping_kprint("0: {*} 1: {*} \n", .{ ttbr0, ttbr1 });
        // old_mapping_kprint("1: {*} \n", .{ttbr1});
        // old_mapping_kprint("{any} \n", .{ttbr1.*});

        proc.TcrReg.setTcrEl(.el1, (proc.TcrReg{ .t0sz = 25, .t1sz = 25, .tg0 = 0, .tg1 = 0 }).asInt());
        proc.MairReg.setMairEl(.el1, (proc.MairReg{ .attr0 = 0xFF, .attr1 = 0x0, .attr2 = 0x0, .attr3 = 0x0, .attr4 = 0x0 }).asInt());

        proc.dsb();
        proc.isb();

        proc.invalidateOldPageTableEntries();
        // proc.invalidateMmuTlbEl1();
        proc.invalidateCache();

        // updating page dirs for kernel and user space
        // toUnsec is bc we are in ttbr1 and can't change with page tables that are also in ttbr1
        proc.setTTBR1(board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0) + no_rom_bl_bin_offset + mmu.toTtbr0(usize, @ptrToInt(ttbr1)));
        proc.setTTBR0(board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0) + no_rom_bl_bin_offset + mmu.toTtbr0(usize, @ptrToInt(ttbr0)));

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

    tests.testUserSpaceMem(10);

    // const demo_var = @as(usize, 4096);
    // kprint("{*}: {x} \n", .{ &demo_var, demo_var });
    // var demo_struct = iD.IssueDemo().init(demo_var);
    // kprint("{any} \n", .{demo_struct});
    // _ = demo_struct;

    // // userspace page allocator test
    // {
    //     const page_alloc_start = utils.ceilRoundToMultiple(board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0) + no_rom_bl_bin_offset + board.config.mem.kernel_space_size, board.config.mem.va_layout.va_user_space_gran.page_size) catch |e| {
    //         kprint("[panic] UserSpaceAllocator start addr calc err: {s}\n", .{@errorName(e)});
    //         k_utils.panic();
    //     };

    //     var user_page_alloc = (UserPageAllocator(204800, board.config.mem.va_layout.va_user_space_gran) catch |e| {
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

    comptime var page_alloc_start = utils.ceilRoundToMultiple(board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0) + no_rom_bl_bin_offset + board.config.mem.kernel_space_size, board.config.mem.va_layout.va_user_space_gran.page_size) catch |e| {
        @compileError(@errorName(e));
    };

    var user_page_alloc = (UserPageAllocator(204800, board.config.mem.va_layout.va_user_space_gran, page_alloc_start) catch |e| {
        kprint("[panic] UserSpaceAllocator init error: {s} \n", .{@errorName(e)});
        k_utils.panic();
    }).init() catch |e| {
        kprint("[panic] UserSpaceAllocator init error: {s} \n", .{@errorName(e)});
        k_utils.panic();
    };

    kprint("[kernel] starting scheduler \n", .{});
    var scheduler = Scheduler(@TypeOf(user_page_alloc)).init(&user_page_alloc);

    var test_proc_pid = scheduler.copyProcessToTaskQueue(0, &testUserProcess) catch |e| {
        kprint("[panic] Scheduler copyProcessToTaskQueue error: {s} \n", .{@errorName(e)});
        k_utils.panic();
    };

    kprint("test process pid: {d} \n", .{test_proc_pid});

    while (true) {
        scheduler.schedule();
    }
}

fn testUserProcess() void {
    old_mapping_kprint("userspace test print \n", .{});
}
comptime {
    @export(intHandle.irqHandler, .{ .name = "irqHandler", .linkage = .Strong });
    @export(intHandle.irqElxSpx, .{ .name = "irqElxSpx", .linkage = .Strong });
}
