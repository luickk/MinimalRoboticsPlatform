pub const boardConfig = @import("boardConfig.zig");

const vaStart: usize = 0xffff000000000000;
pub const config = boardConfig.BoardConfig{
    .board = .raspi3b,
    .mem = boardConfig.BoardMemLayout{
        .va_start = vaStart,

        // the kernel is loaded by into 0x8000 ram by the gpu, so no relocation (or rom) required
        .rom_start_addr = null,
        .rom_size = null,

        // the raspberries addressable memory is all ram
        .ram_start_addr = 0,
        .ram_size = 0x40000000,

        // address to which the bl is loaded if there is NO rom(which is the case for the raspberry 3b)!
        // if there is rom, the bootloader must be loaded to 0x0 (and bl_load_addr = null!)
        .bl_load_addr = 0x80000,

        .ram_layout = .{
            .kernel_space_size = 0x20000000,
            .kernel_space_vs = vaStart,
            // !kernel_space_phys already includes the offset to the kernel space!
            .kernel_space_phys = 0,
            .kernel_space_gran = boardConfig.Granule.Section,

            .user_space_size = 0x20000000,
            .user_space_vs = 0,
            // !user_space_phys already includes the offset to the user space!
            .user_space_phys = 0,
            .user_space_gran = boardConfig.Granule.Fourk,
        },
        .storage_start_addr = 0,
        .storage_size = 0,
    },
    .qemu_launch_command = &[_][]const u8{ "qemu-system-aarch64", "-machine", "raspi3b", "-device", "loader,addr=0x80000,file=zig-out/bin/mergedKernel,cpu-num=0,force-raw=on", "-serial", "stdio", "-display", "none" },
};

pub fn PeriphConfig(secure: bool) type {
    comptime var device_base: usize = 0x3f000000;
    if (secure)
        device_base += config.mem.va_start;

    return struct {
        pub const Pl011 = struct {
            pub const base_address: u64 = device_base + 0x201000;

            // config
            pub const base_clock: u64 = 0x124f800;
            // 9600 slower baud
            pub const baudrate: u32 = 115200;
            pub const data_bits: u32 = 8;
            pub const stop_bits: u32 = 1;
        };

        pub const Timer = struct {
            pub const timerClo: usize = device_base + 0x00003004;
            pub const timerC1: usize = device_base + 0x00003010;
            pub const timerCs: usize = device_base + 0x00003000;
        };

        pub const InterruptController = struct {
            // addresses
            pub const pendingBasic: usize = device_base + 0x0000b200;
            pub const pendingIrq1: usize = device_base + 0x0000b204;
            pub const pendingIrq2: usize = device_base + 0x0000b208;

            pub const enableIrq1: usize = device_base + 0x0000b210;
            pub const enableIrq2: usize = device_base + 0x0000b214;
            pub const enableIrqBasic: usize = device_base + 0x0000b218;
        };
    };
}
