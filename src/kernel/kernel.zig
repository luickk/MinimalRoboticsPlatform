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
        kprint("error reading _stack_top label\n", .{});
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
    var ttbr1 = mmu.PageDir.init(.{ .base_addr = _k_ttbr1_dir, .page_shift = 12, .table_shift = 9 }) catch |e| {
        kprint("Page table init error, {s}\n", .{@errorName(e)});
        k_utils.panic();
    };
    ttbr1.zeroPgDir();
    // ttbr1.newTransLvl(.{ .trans_lvl = .first_lvl, .virt_start_addr = addr.vaStart, .flags = mmu.MmuFlags.mmTypePageTable });

    // mapping general kernel mem
    ttbr1.populateTransLvl(.{ .trans_lvl = .first_lvl, .pop_type = .section, .virt_start_addr = addr.vaStart, .virt_end_addr = addr.vaStart + addr.rpBase, .phys_addr = 0, .flags = mmu.MmuFlags.mmuFlags }) catch |e| {
        kprint("populateTransLvl err: {s} \n", .{@errorName(e)});
        k_utils.panic();
    };
    // mapping devices from base address
    ttbr1.populateTransLvl(.{ .trans_lvl = .first_lvl, .pop_type = .section, .virt_start_addr = addr.vaStart + addr.rpBase, .virt_end_addr = addr.vaStart + 0x40000000, .phys_addr = addr.rpBase, .flags = mmu.MmuFlags.mmuFlags }) catch |e| {
        kprint("populateTransLvl err: {s} \n", .{@errorName(e)});
        k_utils.panic();
    };

    // ttbr1.populateTransLvl(.{ .trans_lvl = .third_lvl, .pop_type = .page, .virt_start_addr = addr.vaStart, .virt_end_addr = addr.vaStart + ttbr1.descriptors_per_table * ttbr1.page_size, .phys_addr = 0, .flags = mmu.MmuFlags.mmutPteFlags }) catch |e| {
    //     kprint("populateTransLvl err: {s} \n", .{@errorName(e)});
    //     k_utils.panic();
    // };

    proc.invalidateDCache(_k_ttbr1_dir, ttbr1.pg_dir.len);
    kprint("{x} \n", .{_k_ttbr1_dir});

    proc.setTTBR1(_k_ttbr1_dir);
    proc.exceptionSvc();

    kprint("kernel boot complete \n", .{});
    while (true) {}
}
