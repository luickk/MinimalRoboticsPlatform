pub const boardConfig = @import("boardConfig.zig");

// mmu starts at lvl1 for which 0xFFFFFF8000000000 is the lowest possible va
const vaStart: usize = 0xFFFFFF8000000000;
pub const config = boardConfig.BoardConfig{
    .board = .qemuVirt,
    .mem = boardConfig.BoardConfig.BoardMemLayout{
        .va_start = vaStart,

        .bl_stack_size = 0x10000,
        .k_stack_size = 0x100000,

        .has_rom = true,
        // qemus machine has a rom with 1 gb size
        .rom_start_addr = 0,
        .rom_size = 0x40000000,
        // since the bootloader is loaded at 0x no bl_load_addr is required
        // (currently only supported for boot without rom)
        .bl_load_addr = null,

        // according to qemu docs ram starts at 1gib
        .ram_start_addr = 0x40000000,
        // 0x100000000
        .ram_size = 0x40000000,

        .kernel_space_size = 0x20000000,
        .user_space_size = 0x20000000,

        .va_layout = .{
            .va_kernel_space_size = 0x80000000,
            .va_kernel_space_gran = boardConfig.Granule.Fourk,

            .va_user_space_size = 0x80000000,
            .va_user_space_gran = boardConfig.Granule.Fourk,
        },
        .storage_start_addr = 0,
        .storage_size = 0,
    },
    // arm_gt, gic
    //
    .qemu_launch_command = &[_][]const u8{ "qemu-system-aarch64", "-machine", "virt", "-m", "10G", "-cpu", "cortex-a53", "-device", "loader,file=zig-out/bin/mergedKernel,cpu-num=0,force-raw=on", "-serial", "stdio", "-display", "none", "-d", "trace:arm_gt*", "-D", "./log.txt" },
};

pub fn PeriphConfig(comptime addr_space: boardConfig.AddrSpace) type {
    const new_ttbr1_device_base_ = 0x30000000;
    comptime var device_base_tmp: usize = 0x8000000;

    // in ttbr1 all periph base is mapped to 0x40000000
    if (addr_space.isKernelSpace()) device_base_tmp = config.mem.va_start + new_ttbr1_device_base_;

    return struct {
        pub const device_base_size: usize = 0xA000000;
        pub const device_base: usize = device_base_tmp;
        pub const new_ttbr1_device_base = new_ttbr1_device_base_;

        pub const Pl011 = struct {
            pub const base_address: u64 = device_base + 0x1000000;

            pub const base_clock: u64 = 0x16e3600;
            // 9600 slower baud
            pub const baudrate: u32 = 115200;
            pub const data_bits: u32 = 8;
            pub const stop_bits: u32 = 1;
        };
        pub const GicV2 = struct {
            pub const base_address: u64 = device_base + 0;

            pub const intMax: usize = 64;
            pub const intNoPpi0: usize = 32;
            pub const intNoSpi0: usize = 16;
            pub const priShift: usize = 4;
        };
    };
}
