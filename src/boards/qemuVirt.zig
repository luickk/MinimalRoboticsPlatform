pub const boardConfig = @import("boardConfig.zig");

const vaStart: usize = 0xffff000000000000;
pub const config = boardConfig.BoardConfig{
    .board = .qemuVirt,
    .mem = boardConfig.BoardMemLayout{
        .va_start = vaStart,

        // qemus machine has a rom with 1 gb size
        .rom_start_addr = 0,
        .rom_size = 0x40000000,
        // according to qemu docs ram starts at 1gib
        .ram_start_addr = 0x40000000,
        .ram_size = 0x80000000,

        // since the bootloader is loaded at 0x no bl_load_addr is required
        // (currently only supported for boot without rom)
        .bl_load_addr = null,

        .ram_layout = .{
            .kernel_space_size = 0x40000000,
            .kernel_space_vs = vaStart,
            // !kernel_space_phys already includes the offset to the kernel space!
            .kernel_space_phys = 0,
            .kernel_space_gran = boardConfig.Granule.Section,

            .user_space_size = 0x40000000,
            .user_space_vs = 0,
            // !user_space_phys already includes the offset to the user space!
            .user_space_phys = 0,
            .user_space_gran = boardConfig.Granule.Fourk,
        },
        .storage_start_addr = 0,
        .storage_size = 0,
    },
    // todo => add compiltime selectable serial output interface
    .qemu_launch_command = &[_][]const u8{ "qemu-system-aarch64", "-machine", "virt", "-m", "10G", "-cpu", "cortex-a53", "-device", "loader,file=zig-out/bin/mergedKernel,cpu-num=0,force-raw=on", "-serial", "stdio", "-display", "none" },
};

pub fn PeriphConfig(secure: bool) type {
    comptime var device_base: usize = 0;
    if (secure)
        device_base += config.mem.va_start;

    return struct {
        pub const Pl011 = struct {
            pub const base_address: u64 = device_base + 0x9000000;

            pub const base_clock: u64 = 0x16e3600;
            // 9600 slower baud
            pub const baudrate: u32 = 115200;
            pub const data_bits: u32 = 8;
            pub const stop_bits: u32 = 1;
        };
    };
}
