const std = @import("std");
const periph = @import("peripherals");
const utils = @import("utils");
const k_utils = @import("utils.zig");

const kprint = periph.serial.kprint;
// kernel services
const KernelAllocator = @import("memory.zig").KernelAllocator;
const intHandle = @import("intHandle.zig");
const b_options = @import("build_options");
const board = @import("board");

const intController = periph.intController;
const timer = periph.timer;
const proc = periph.processor;
const mmu = periph.mmu;

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

    if (mmu.toUnsecure(usize, _kernel_end) > board.Info.mem.ram_len) {
        kprint("[panic] kernel exceeding ram mem (0x{x})\n", .{mmu.toUnsecure(usize, _kernel_end)});
        k_utils.panic();
    }

    var current_el = proc.getCurrentEl();
    if (current_el != 1) {
        kprint("[panic] el must be 1! (it is: {d})\n", .{current_el});
        proc.panic();
    }

    timer.initTimer();
    kprint("[kernel] timer inited \n", .{});
    intController.initIc();
    kprint("[kernel] ic inited \n", .{});
    const kernel_space_mapping = mmu.Mapping{
        .mem_size = board.Info.mem.ram_layout.kernel_space_size,
        .virt_start_addr = board.Info.mem.ram_layout.kernel_space_vs,
        .phys_addr = board.Info.mem.ram_layout.kernel_space_phys,
        .granule = board.Info.mem.ram_layout.kernel_space_gran,
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
        .mem_size = board.Info.mem.ram_layout.user_space_size,
        .virt_start_addr = board.Info.mem.ram_layout.user_space_vs,
        .phys_addr = board.Info.mem.ram_layout.user_space_phys,
        .granule = board.Info.mem.ram_layout.user_space_gran,
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

    proc.setTcrEl1((mmu.TcrReg{ .t0sz = 16, .t1sz = 16, .tg0 = 2 }).asInt());
    proc.resetMmuTlbEl1();
    // updating page dirs for kernel and user space
    proc.setTTBR1(_k_ttbr1_dir);
    proc.setTTBR0(_u_ttbr0_dir);

    kprint("[kernel] kernel boot complete \n", .{});

    @intToPtr(*usize, 0x10000000).* = 100;
    if (@intToPtr(*usize, 0x10000000).* == 100)
        kprint("[kTEST] write to userspace successfull \n", .{});
    while (true) {}
}
