const std = @import("std");
const periph = @import("peripherals");
const utils = @import("utils");
const k_utils = @import("utils.zig");

const kprint = periph.serial.kprint;
// kernel services
const KernelAllocator = @import("memory.zig").KernelAllocator;
const intHandle = @import("intHandle.zig");
const intController = periph.intController;
const timer = periph.timer;
const addr = periph.rbAddr;
const proc = periph.processor;
const mmu = periph.mmu;

export fn kernel_main() callconv(.Naked) noreturn {
    kprint("kernel started! \n", .{});

    // // get address of external linker script variable which marks stack-top and heap-start
    // const mem_start: usize = @ptrToInt(@extern(?*u8, .{ .name = "_stack_top" }) orelse {
    //     kprint("error reading _stack_top label\n", .{});
    //     unreachable;
    // });
    const _k_ttbr1_dir: usize = @ptrToInt(@extern(?*u8, .{ .name = "_kernel_ttbr1_dir" }) orelse {
        kprint("error reading _kernel_ttbr1_dir label\n", .{});
        unreachable;
    });
    const _u_ttbr0_dir: usize = @ptrToInt(@extern(?*u8, .{ .name = "_user_ttbr0_dir" }) orelse {
        kprint("error reading _user_ttbr0_dir label\n", .{});
        unreachable;
    });
    var current_el = proc.getCurrentEl();
    if (current_el != 1) {
        kprint("el must be 1! (it is: {d})\n", .{current_el});
        proc.panic();
    }

    timer.initTimer();
    kprint("timer inited \n", .{});
    intController.initIc();
    kprint("ic inited \n", .{});

    // var alloc = KernelAllocator(0x40000000, 512, addr.vaStart).init(mem_start) catch |err| utils.printErrNoReturn(err);
    // _ = alloc;
    // kprint("kernel allocator inited \n", .{});

    // creating virtual address space for kernel
    var kernel_mapping = mmu.PageDir.Mapping{ .mem_size = 0x40000000, .virt_start_addr = addr.vaStart, .phys_addr = 0 };

    var ttbr1 = mmu.PageDir.init(.{ .base_addr = _k_ttbr1_dir, .page_shift = 12, .mapping = kernel_mapping, .table_shift = 9 }) catch |e| {
        kprint("Page table init error, {s}\n", .{@errorName(e)});
        k_utils.panic();
    };

    ttbr1.zeroPgDir();

    // mapping general kernel mem
    ttbr1.populateTableWithPhys(.{ .trans_lvl = .first_lvl, .pop_type = .section, .mapping = kernel_mapping, .flags = mmu.MmuFlags.mmuFlags }) catch |e| {
        kprint("populateTableWithPhys err: {s} \n", .{@errorName(e)});
        k_utils.panic();
    };

    var user_mapping = mmu.PageDir.Mapping{ .mem_size = 0x40000000, .virt_start_addr = 0, .phys_addr = 0x40000000 };
    var ttbr0 = mmu.PageDir.init(.{ .base_addr = _u_ttbr0_dir, .page_shift = 12, .mapping = user_mapping, .table_shift = 9 }) catch |e| {
        kprint("Page table init error: {s}\n", .{@errorName(e)});
        k_utils.panic();
    };
    ttbr0.zeroPgDir();

    ttbr0.mapMem() catch |e| {
        kprint("memory mapping error: {s} \n", .{@errorName(e)});
        k_utils.panic();
    };

    // // kprint("i: {d}, i_max: {d}, ss: {d}\n", .{ 0, 0, 0 });
    // ttbr0.populateTableWithTables(.{ .trans_lvl = .first_lvl, .mapping = user_mapping, .flags = mmu.MmuFlags.mmTypePageTable }) catch |e| {
    //     kprint("populateTableWithTables error:, {s}\n", .{@errorName(e)});
    //     k_utils.panic();
    // };

    // ttbr0.populateTableWithTables(.{ .trans_lvl = .second_lvl, .mapping = user_mapping, .flags = mmu.MmuFlags.mmTypePageTable }) catch |e| {
    //     kprint("populateTableWithTables error: {s}\n", .{@errorName(e)});
    //     k_utils.panic();
    // };

    // // mapping user space
    // ttbr0.populateTableWithPhys(.{ .trans_lvl = .third_lvl, .pop_type = .page, .mapping = user_mapping, .flags = mmu.MmuFlags.mmTypePageTable }) catch |e| {
    //     kprint("populateTableWithPhys err: {s} \n", .{@errorName(e)});
    //     k_utils.panic();
    // };

    proc.resetMmuTlbEl1();

    // updating page dirs for kernel and user space
    proc.setTTBR1(_k_ttbr1_dir);
    proc.setTTBR0(_u_ttbr0_dir);

    kprint("kernel boot complete \n", .{});

    kprint("wiritng to new userspace mem (test): \n", .{});
    @intToPtr(*usize, 8).* = 100;
    kprint("done writing: \n", .{});
    while (true) {}
}
