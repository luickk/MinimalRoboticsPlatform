const std = @import("std");
const utils = @import("utils");
const board = @import("board");
const kernelThreads = @import("kernelThreads");
const setupRoutines = @import("setupRoutines");

// kernel services
const sharedKernelServices = @import("sharedKernelServices");
const Scheduler = sharedKernelServices.Scheduler;
const SysCallsTopicsInterface = sharedKernelServices.SysCallsTopicsInterface;
const StatusControl = sharedKernelServices.StatusControl;
// KernelAllocator and UserPageAllocator types are inited in sharedKernelServices!.
const KernelAllocator = sharedKernelServices.KernelAllocator;
const UserPageAllocator = sharedKernelServices.UserPageAllocator;
const k_utils = @import("utils.zig");
const tests = @import("tests.zig");
const intHandle = @import("kernelIntHandler.zig");
const sysCalls = @import("sysCalls.zig");
const b_options = @import("build_options");

const kpi = @import("kpi");

const alignForward = std.mem.alignForward;

// arm specific periphs
const arm = @import("arm");
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
// const bcm2835IntController = arm.bcm2835IntController.InterruptController(.ttbr1);

var user_page_alloc = UserPageAllocator.init() catch |e| {
    @compileError(@errorName(e));
};

// pointer is now global, ! kernel main lifetime needs to be equal to schedulers lt.. !
export var scheduler: *Scheduler = undefined;
export var status_control: *StatusControl = undefined;
export var topics: *SysCallsTopicsInterface = undefined;

const apps = blk: {
    var apps_addresses = [_][]const u8{undefined} ** b_options.apps.len;
    for (b_options.apps, 0..) |app, i| {
        const app_file = @embedFile("bins/apps/" ++ app);
        apps_addresses[i] = app_file;
    }

    break :blk apps_addresses;
};
const actions = blk: {
    var action_addresses = [_][]const u8{undefined} ** b_options.actions.len;
    for (b_options.actions, 0..) |action, i| {
        const app_file = @embedFile("bins/actions/" ++ action);
        action_addresses[i] = app_file;
    }

    break :blk action_addresses;
};

// todo => add error handling such that try can be used in such "main" funcitons
export fn kernel_main(boot_without_rom_new_kernel_loc: usize) linksection(".text.kernel_main") callconv(.C) noreturn {
    // !! kernel sp is set in the Bootloader!!

    {
        const _exc_vec_label: usize = @intFromPtr(@extern(?*u8, .{ .name = "_exception_vector_table" }) orelse {
            kprint("[panic] error reading _exception_vector_table label\n", .{});
            k_utils.panic();
        });

        ProccessorRegMap.setExceptionVec(_exc_vec_label);
    }

    // required for every page table modification, since the absolute memory location needs to be given to the mmu
    const kernel_lma_offset = boot_without_rom_new_kernel_loc + board.config.mem.ram_start_addr;

    const _kernel_space_start: usize = @intFromPtr(@extern(?*u8, .{ .name = "_kernel_space_start" }) orelse {
        old_mapping_kprint("[panic] error reading _kernel_space_start label\n", .{});
        k_utils.panic();
    });

    var kspace_alloc = KernelAllocator.init(std.mem.alignForward(usize, _kernel_space_start, 8) + board.config.mem.k_stack_size) catch |e| {
        old_mapping_kprint("[panic] KernelAllocator init error: {s}\n", .{@errorName(e)});
        k_utils.panic();
    };

    // mmu config block
    {
        const ttbr1 = blk: {
            const page_table = mmu.PageTable(board.config.mem.va_kernel_space_page_table_capacity, board.config.mem.va_kernel_space_gran) catch |e| {
                old_mapping_kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            };

            const ttbr1_mem = @as(*volatile [page_table.totaPageTableSize]usize, @ptrCast((kspace_alloc.alloc(usize, page_table.totaPageTableSize, board.config.mem.va_kernel_space_gran.page_size) catch |e| {
                old_mapping_kprint("[panic] Page table kalloc error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            }).ptr));

            // mapping general kernel mem (inlcuding device base)
            var ttbr1_write = page_table.init(ttbr1_mem, kernel_lma_offset) catch |e| {
                old_mapping_kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            };

            {
                // creating virtual address space for kernel
                const kernel_space_mapping = mmu.Mapping{
                    .mem_size = board.config.mem.kernel_space_size,
                    .pointing_addr_start = kernel_lma_offset,
                    .virt_addr_start = 0,
                    .granule = board.config.mem.va_kernel_space_gran,
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
                // creating virtual address space for periphs
                const periph_mapping = mmu.Mapping{
                    .mem_size = board.PeriphConfig(.ttbr0).device_base_size,
                    .pointing_addr_start = board.PeriphConfig(.ttbr0).device_base,
                    .virt_addr_start = board.PeriphConfig(.ttbr0).new_ttbr1_device_base,
                    .granule = board.config.mem.va_kernel_space_gran,
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
            const page_table = mmu.PageTable(board.config.mem.va_user_space_page_table_capacity, board.config.mem.va_user_space_gran) catch |e| {
                @compileError(@errorName(e));
            };
            const ttbr0_mem = @as(*volatile [page_table.totaPageTableSize]usize, @ptrCast((kspace_alloc.alloc(usize, page_table.totaPageTableSize, board.config.mem.va_user_space_gran.page_size) catch |e| {
                old_mapping_kprint("[panic] sPage table kalloc error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            }).ptr));

            // MMU page dir config
            var page_table_write = page_table.init(ttbr0_mem, kernel_lma_offset) catch |e| {
                old_mapping_kprint("[panic] Page table init error: {s}\n", .{@errorName(e)});
                k_utils.panic();
            };

            const user_space_mapping = mmu.Mapping{
                .mem_size = board.config.mem.user_space_size,
                .pointing_addr_start = kernel_lma_offset + board.config.mem.kernel_space_size,
                .virt_addr_start = 0,
                .granule = board.config.mem.va_user_space_gran,
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
        ProccessorRegMap.setTTBR1(kernel_lma_offset + utils.toTtbr0(usize, @intFromPtr(ttbr1)));
        ProccessorRegMap.setTTBR0(kernel_lma_offset + utils.toTtbr0(usize, @intFromPtr(ttbr0)));

        ProccessorRegMap.dsb();
        ProccessorRegMap.isb();
        ProccessorRegMap.nop();
        ProccessorRegMap.nop();
    }

    kprint("[kernel] page tables updated! \n", .{});

    const current_el = ProccessorRegMap.getCurrentEl();
    if (current_el != 1) {
        kprint("[panic] el must be 1! (it is: {d})\n", .{current_el});
        ProccessorRegMap.panic();
    }

    kprint("[kernel] kernel boot complete \n", .{});

    tests.testUserPageAlloc(&user_page_alloc) catch |e| {
        kprint("[panic] testUserPageAlloc test error: {s} \n", .{@errorName(e)});
        k_utils.panic();
    };

    var scheduler_tmp = Scheduler.init(&user_page_alloc, kernel_lma_offset);
    scheduler = &scheduler_tmp;

    {
        var topics_tmp = SysCallsTopicsInterface.init(&user_page_alloc, scheduler) catch |e| {
            kprint("[panic] SysCallsTopicsInterface init error: {s} \n", .{@errorName(e)});
            k_utils.panic();
        };
        topics = &topics_tmp;
    }

    {
        var status_control_tmp = StatusControl.init(&kspace_alloc) catch |e| {
            kprint("[panic] StatusControl init error: {s} \n", .{@errorName(e)});
            k_utils.panic();
        };
        status_control = &status_control_tmp;
    }

    {
        kprint("[kernel] starting scheduler \n", .{});
        // boot process = this process
        scheduler.configRootBootProcess();
        scheduler.initAppsInScheduler(&apps, topics.mem_pool) catch |e| {
            kprint("[panic] Scheduler initAppsInScheduler error: {s} \n", .{@errorName(e)});
            k_utils.panic();
        };

        // scheduler.initActionsInScheduler(&actions, topics.mem_pool) catch |e| {
        //     kprint("[panic] actions init error: {s} \n", .{@errorName(e)});
        //     k_utils.panic();
        // };

        scheduler.initProcessCounter();
    }

    // kernel setup routines execution
    inline for (setupRoutines.setupRoutines) |routine| {
        routine(scheduler);
    }

    board.driver.timerDriver.initTimerDriver() catch |e| {
        kprint("[panic] timer driver error: {s} \n", .{@errorName(e)});
        k_utils.panic();
    };
    kprint("[kernel] timer inited \n", .{});

    if (board.driver.secondaryInterruptConrtollerDriver) |secondary_ic| {
        secondary_ic.initIcDriver() catch |e| {
            kprint("[panic] initIcDriver error: {s} \n", .{@errorName(e)});
            k_utils.panic();
        };
    }

    // kernel thread scheduler init
    inline for (kernelThreads.threads) |generic_thread| {
        scheduler.createKernelThread(&kspace_alloc, generic_thread, .{scheduler}) catch |e| {
            kprint("[panic] kernel thread createKernelThread error: {s} \n", .{@errorName(e)});
            k_utils.panic();
        };
    }

    var counter: usize = 0;
    while (true) {
        kprint("while counter: {d} \n", .{counter});
        // kprint("timer: {d} irq: {d} \n", .{ bcm2835Timer.RegMap.timerCs.*, bcm2835IntController.RegMap.enableIrq1.* });
        counter += 1;
    }
}

comptime {
    @export(intHandle.trapHandler, .{ .name = "trapHandler", .linkage = .Strong });
}
