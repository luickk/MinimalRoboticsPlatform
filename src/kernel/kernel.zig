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

// arm specific periphs
const arm = @import("arm");
const gic = arm.gicv2.Gic(.ttbr1);
const InterruptIds = gic.InterruptIds;
const gt = arm.genericTimer;
const ProccessorRegMap = arm.processor.ProccessorRegMap;
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

const apps = blk: {
    var apps_addresses = [_][]const u8{undefined} ** b_options.apps.len;
    for (b_options.apps) |app, i| {
        const app_file = @embedFile("bins/" ++ app);
        apps_addresses[i] = app_file;
    }

    break :blk apps_addresses;
};

export fn kernel_main() linksection(".text.kernel_main") callconv(.Naked) noreturn {
    // !! kernel sp is inited in the Bootloader!!

    const _kernel_space_start: usize = @ptrToInt(@extern(?*u8, .{ .name = "_kernel_space_start" }) orelse {
        old_mapping_kprint("[panic] error reading _kernel_space_start label\n", .{});
        k_utils.panic();
    });
    const kernel_bin_size = mmu.toTtbr0(usize, _kernel_space_start);

    // kernelspace allocator test
    var kspace_alloc = KernelAllocator.init(_kernel_space_start + board.config.mem.k_stack_size + 0x50000, board.config.mem.kernel_space_size - kernel_bin_size - board.config.mem.k_stack_size, 0x10000) catch |e| {
        old_mapping_kprint("[panic] KernelAllocator init error: {s}\n", .{@errorName(e)});
        k_utils.panic();
    };

    // mmu config block
    {
        const ttbr1 = blk: {
            const page_table = mmu.PageTable(board.config.mem.va_layout.va_kernel_space_size, board.config.mem.va_layout.va_kernel_space_gran) catch |e| {
                old_mapping_kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            };

            const ttbr1_mem = @ptrCast(*volatile [page_table.totaPageTableSize]usize, (kspace_alloc.alloc(usize, page_table.totaPageTableSize, board.config.mem.va_layout.va_kernel_space_gran.page_size) catch |e| {
                old_mapping_kprint("[panic] Page table kalloc error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            }).ptr);

            // mapping general kernel mem (inlcuding device base)
            var ttbr1_write = page_table.init(ttbr1_mem, board.config.mem.ram_start_addr) catch |e| {
                old_mapping_kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            };

            {
                // creating virtual address space for kernel
                const kernel_space_mapping = mmu.Mapping{
                    .mem_size = board.config.mem.kernel_space_size,
                    .pointing_addr_start = board.config.mem.ram_start_addr,
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

            break :blk ttbr1_mem;
        };

        const ttbr0 = blk: {
            const page_table = mmu.PageTable(board.config.mem.va_layout.va_user_space_size, board.config.mem.va_layout.va_user_space_gran) catch |e| {
                @compileError(@errorName(e));
            };
            const ttbr0_mem = @ptrCast(*volatile [page_table.totaPageTableSize]usize, (kspace_alloc.alloc(usize, page_table.totaPageTableSize, board.config.mem.va_layout.va_user_space_gran.page_size) catch |e| {
                old_mapping_kprint("[panic] sPage table kalloc error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            }).ptr);

            // MMU page dir config
            var page_table_write = page_table.init(ttbr0_mem, board.config.mem.ram_start_addr) catch |e| {
                old_mapping_kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            };

            const user_space_mapping = mmu.Mapping{
                .mem_size = board.config.mem.user_space_size,
                .pointing_addr_start = board.config.mem.ram_start_addr + board.config.mem.kernel_space_size,
                .virt_addr_start = 0,
                .granule = board.config.mem.va_layout.va_user_space_gran,
                .addr_space = .ttbr0,
                .flags_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .only_el1_read_write, .attrIndex = .mair0 },
                .flags_non_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .only_el1_read_write },
            };
            page_table_write.mapMem(user_space_mapping) catch |e| {
                old_mapping_kprint("[panic] Page table write error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            };
            break :blk ttbr0_mem;
        };

        ProccessorRegMap.TcrReg.setTcrEl(.el1, (ProccessorRegMap.TcrReg{ .t0sz = 25, .t1sz = 25, .tg0 = 0, .tg1 = 0 }).asInt());
        ProccessorRegMap.MairReg.setMairEl(.el1, (ProccessorRegMap.MairReg{ .attr0 = 0xFF, .attr1 = 0x0, .attr2 = 0x0, .attr3 = 0x0, .attr4 = 0x0 }).asInt());

        ProccessorRegMap.dsb();
        ProccessorRegMap.isb();

        ProccessorRegMap.invalidateOldPageTableEntries();
        // ProccessorRegMap.invalidateMmuTlbEl1();
        ProccessorRegMap.invalidateCache();

        // updating page dirs for kernel and user space
        // toUnsec is bc we are in ttbr1 and can't change with page tables that are also in ttbr1
        ProccessorRegMap.setTTBR1(board.config.mem.ram_start_addr + mmu.toTtbr0(usize, @ptrToInt(ttbr1)));
        ProccessorRegMap.setTTBR0(board.config.mem.ram_start_addr + mmu.toTtbr0(usize, @ptrToInt(ttbr0)));

        ProccessorRegMap.dsb();
        ProccessorRegMap.isb();
        ProccessorRegMap.nop();
        ProccessorRegMap.nop();
    }
    kprint("[kernel] page tables updated! \n", .{});

    {
        const _exc_vec_label: usize = @ptrToInt(@extern(?*u8, .{ .name = "_exception_vector_table" }) orelse {
            kprint("[panic] error reading _exception_vector_table label\n", .{});
            k_utils.panic();
        });
        ProccessorRegMap.setExceptionVec(_exc_vec_label);
    }

    var current_el = ProccessorRegMap.getCurrentEl();
    if (current_el != 1) {
        kprint("[panic] el must be 1! (it is: {d})\n", .{current_el});
        ProccessorRegMap.panic();
    }

    kprint("[kernel] kernel boot complete \n", .{});

    var user_page_alloc = UserPageAllocator.init(board.config.mem.user_space_size, board.config.mem.va_layout.va_user_space_gran) catch |e| {
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
    // ProccessorRegMap.exceptionSvc();

    if (board.config.board == .qemuVirt) {
        gic.init() catch |e| {
            kprint("[panic] gic init error: {s}\n", .{@errorName(e)});
            k_utils.panic();
        };

        gic.Gicd.gicdConfig(InterruptIds.non_secure_physical_timer, 0x2) catch |e| {
            kprint("[panic] gicd gicdConfig error: {s}\n", .{@errorName(e)});
            k_utils.panic();
        };
        gic.Gicd.gicdSetPriority(InterruptIds.non_secure_physical_timer, 0) catch |e| {
            kprint("[panic] gicd setPriority error: {s}\n", .{@errorName(e)});
            k_utils.panic();
        };
        gic.Gicd.gicdSetTarget(InterruptIds.non_secure_physical_timer, 1) catch |e| {
            kprint("[panic] gicd setTarget error: {s}\n", .{@errorName(e)});
            k_utils.panic();
        };

        gic.Gicd.gicdClearPending(InterruptIds.non_secure_physical_timer) catch |e| {
            kprint("[panic] gicd clearPending error: {s}\n", .{@errorName(e)});
            k_utils.panic();
        };

        gic.Gicd.gicdEnableInt(InterruptIds.non_secure_physical_timer) catch |e| {
            kprint("[panic] gicdEnableInt address calc error: {s}\n", .{@errorName(e)});
            k_utils.panic();
        };

        ProccessorRegMap.DaifReg.setDaifClr(.{
            .debug = true,
            .serr = true,
            .irqs = true,
            .fiqs = true,
        });
    }

    if (board.config.board == .raspi3b) {
        bcm2835IntController.init();
        kprint("[kernel] ic inited \n", .{});
    }

    kprint("[kernel] starting scheduler \n", .{});

    scheduler.initAppsInScheduler(0, &apps) catch |e| {
        kprint("[panic] Scheduler initAppsInScheduler error: {s} \n", .{@errorName(e)});
        k_utils.panic();
    };

    scheduler.initProcessCounter();

    if (board.config.board == .qemuVirt) {
        gt.setupGt();
        kprint("[kernel] timer inited \n", .{});
    }

    if (board.config.board == .raspi3b) {
        bcm2835Timer.initTimer();
        kprint("[kernel] timer inited \n", .{});
    }

    while (true) {
        // kprint("while \n", .{});
        // kprint("while {d} \n", .{loltest});
        // kprint("while el: {d} \n", .{ProccessorRegMap.getCurrentEl()});
    }
}

comptime {
    @export(intHandle.irqHandler, .{ .name = "irqHandler", .linkage = .Strong });
    @export(intHandle.irqElxSpx, .{ .name = "irqElxSpx", .linkage = .Strong });
}
