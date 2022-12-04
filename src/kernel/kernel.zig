const std = @import("std");
const utils = @import("utils");

const board = @import("board");

// kernel services
const sharedKServices = @import("sharedKServices");
const Scheduler = sharedKServices.Scheduler;
// KernelAllocator and UserPageAllocator types are inited in sharedKServices!.
const KernelAllocator = sharedKServices.KernelAllocator;
const UserPageAllocator = sharedKServices.UserPageAllocator;
const k_utils = @import("utils.zig");
const tests = @import("tests.zig");
const intHandle = @import("kernelIntHandler.zig");
const b_options = @import("build_options");
const kernel_bin_size = b_options.kernel_bin_size;
const bl_bin_size = b_options.bl_bin_size;

// arm specific periphs
const arm = @import("arm");
const gic = arm.gicv2.Gic(.ttbr1);
const gt = arm.genericTimer;
const proc = arm.processor.ProccessorRegMap(.el1);
const mmu = arm.mmu;

// general peripherals
const periph = @import("periph");
// pre_kernel_page_table_init_kprint...
// uses userspace addresses(ttbr0), since those are still identity mapped
// to access peripherals
const old_mapping_kprint = periph.uart.UartWriter(.ttbr0).kprint;
const kprint = periph.uart.UartWriter(.ttbr1).kprint;

// raspberry specific periphs
const bcm2835IntController = arm.bcm2835IntController.InterruptController(.ttbr1);
const bcm2835Timer = @import("board/raspi3b/timer.zig");

// globals
export var scheduler: *Scheduler = undefined;

export fn kernel_main() linksection(".text.kernel_main") callconv(.Naked) noreturn {
    // !! kernel sp is inited in the Bootloader!!

    // if there is rom, the bootloader binary has to be taken into account for the offset
    comptime var no_rom_bl_bin_offset = 0;
    if (!board.config.mem.has_rom) no_rom_bl_bin_offset = bl_bin_size;

    // kernelspace allocator test
    var kspace_alloc = blk: {
        const _kernel_space_start: usize = @ptrToInt(@extern(?*u8, .{ .name = "_kernel_space_start" }) orelse {
            old_mapping_kprint("[panic] error reading _kernel_space_start label\n", .{});
            k_utils.panic();
        });

        var kernel_alloc = KernelAllocator.init(_kernel_space_start + board.config.mem.k_stack_size) catch |e| {
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

    {
        const _exc_vec_label: usize = @ptrToInt(@extern(?*u8, .{ .name = "_exception_vector_table" }) orelse {
            kprint("[panic] error reading _exception_vector_table label\n", .{});
            k_utils.panic();
        });
        proc.setExceptionVec(_exc_vec_label);
    }

    var current_el = proc.getCurrentEl();
    if (current_el != 1) {
        kprint("[panic] el must be 1! (it is: {d})\n", .{current_el});
        proc.panic();
    }

    kprint("[kernel] kernel boot complete \n", .{});

    var user_page_alloc = UserPageAllocator.init() catch |e| {
        kprint("[panic] UserSpaceAllocator init error: {s} \n", .{@errorName(e)});
        k_utils.panic();
    };

    // pointer is now global, ! kernel main lifetime needs to be equal to schedulers.. !
    var scheduler_tmp = Scheduler.init(&user_page_alloc);
    scheduler = &scheduler_tmp;

    // // tests
    // tests.testUserSpaceMem(10);
    // tests.testUserPageAlloc(&user_page_alloc) catch |e| {
    //     kprint("[panic] testUserPageAlloc test error: {s} \n", .{@errorName(e)});
    //     k_utils.panic();
    // };
    // proc.exceptionSvc();

    if (board.config.board == .qemuVirt) {
        gic.init() catch |e| {
            kprint("[panic] gic init error: {s}\n", .{@errorName(e)});
            k_utils.panic();
        };

        gic.Gicd.gicdConfig(gic.InterruptIds.non_secure_physical_timer, 0x2);
        gic.Gicd.gicdSetPriority(gic.InterruptIds.non_secure_physical_timer, 0);
        gic.Gicd.gicdSetTarget(gic.InterruptIds.non_secure_physical_timer, 1) catch |e| {
            kprint("[panic] gicd setTarget error: {s}\n", .{@errorName(e)});
            k_utils.panic();
        };

        gic.Gicd.gicdEnableInt(gic.InterruptIds.non_secure_physical_timer) catch |e| {
            kprint("[panic] gicdEnableInt address calc error: {s}\n", .{@errorName(e)});
            k_utils.panic();
        };

        proc.DaifReg.setDaifClr(.{
            .debug = true,
            .serr = true,
            .irqs = true,
            .fiqs = true,
        });

        gt.setupGt();
    }

    // asm volatile ("WFI");

    if (board.config.board == .raspi3b) {
        bcm2835IntController.init();
        kprint("[kernel] ic inited \n", .{});

        bcm2835Timer.initTimer();
        kprint("[kernel] timer inited \n", .{});
    }

    kprint("[kernel] starting scheduler \n", .{});

    var test_proc_pid = scheduler.copyProcessToTaskQueue(0, &testUserProcess) catch |e| {
        kprint("[panic] Scheduler copyProcessToTaskQueue error: {s} \n", .{@errorName(e)});
        k_utils.panic();
    };
    var test_proc_pid_ts = scheduler.copyProcessToTaskQueue(0, &testUserProcessTheSecond) catch |e| {
        kprint("[panic] Scheduler copyProcessToTaskQueue error: {s} \n", .{@errorName(e)});
        k_utils.panic();
    };

    kprint("test process pid: {d}, {d} \n", .{ test_proc_pid, test_proc_pid_ts });

    scheduler.initTaskCounter();
    while (true) {
        // kprint("basic pend: {b} 1: {b} 2: {b} \n", .{ @intToPtr(*volatile u32, 0xFFFFFF8030000000).*, @intToPtr(*volatile u32, 0xFFFFFF8030000004).*, @intToPtr(*volatile u32, 0xFFFFFF8030000008).* });
        // kprint("while \n", .{});
        // kprint("lol: {any} \n", .{gic.Gicc.gicv2FindPendingIrq() catch {
        //     unreachable;
        // }});
        // kprint("lol: {any} \n", .{gic.Gicd.gicdProbePending(30) catch {
        //     unreachable;
        // }});
        // scheduler.timerIntEvent();
        // ISR_EL1 or cntp_ctl_el0
        // var x: usize = asm volatile ("mrs %[curr], cntp_ctl_el0"
        //     : [curr] "=r" (-> usize),
        // );
        // kprint("x: {d} \n", .{x});
    }
}

fn testUserProcess() void {
    kprint("userspace test print - ONE 1 \n", .{});
    // kprint("enable 1: {b} 2: {b} basic: {b} \n", .{ @intToPtr(*volatile u32, 0xFFFFFF8030000010).*, @intToPtr(*volatile u32, 0xFFFFFF8030000014).*, @intToPtr(*volatile u32, 0xFFFFFF8030000018).* });
    while (true) {
        // kprint("p1 \n", .{});
    }
}

fn testUserProcessTheSecond() void {
    kprint("userspace test print - TWO 2 \n", .{});
    // kprint("enable 1: {b} 2: {b} basic: {b} \n", .{ @intToPtr(*volatile u32, 0xFFFFFF8030000010).*, @intToPtr(*volatile u32, 0xFFFFFF8030000014).*, @intToPtr(*volatile u32, 0xFFFFFF8030000018).* });
    kprint("current_el: {d} \n", .{proc.getCurrentEl()});
    while (true) {

        // kprint("cs: {b} \n", .{@intToPtr(*volatile u32, 0xFFFFFF8030003000).*});
        // kprint("p2 \n", .{});
    }
}

comptime {
    @export(intHandle.irqHandler, .{ .name = "irqHandler", .linkage = .Strong });
    @export(intHandle.irqElxSpx, .{ .name = "irqElxSpx", .linkage = .Strong });
}
