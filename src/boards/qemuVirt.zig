pub const layout = @import("memLayout.zig");

pub const Info = layout.BoardParams{
    .board = .qemuVirt,
    .mem = layout.BoardMemLayout{
        // qemu raspi is weird since there is no (at least none I could find) layout for the guest memory and only a total of 1gb (which cannot be increased)
        // so I'm just assuming a rom in which the bootloader is loaded of 0x400000b
        .rom_start_addr = 0,
        .rom_len = 0x40000000,

        .ram_start_addr = 0x40000000,
        .ram_len = 0x80000000,

        .ram_layout = .{
            .kernel_space_size = 0x40000000,
            .kernel_space_vs = Addresses.vaStart,
            .kernel_space_phys = 0,
            .kernel_space_gran = layout.Granule.Section,

            .user_space_size = 0x40000000,
            .user_space_vs = 0,
            .user_space_phys = 0x40000000,
            .user_space_gran = layout.Granule.Fourk,
        },
        .storage_start_addr = 0,
        .storage_len = 0,
    },
    .qemu_launch_command = &[_][]const u8{ "qemu-system-aarch64", "-machine", "virt", "-m", "10G", "-cpu", "cortex-a53", "-device", "loader,file=zig-out/bin/mergedKernel,cpu-num=0,force-raw=on", "-serial", "stdio", "-display", "none" },
};

pub const Addresses = struct {
    pub const vaStart: usize = 0xffff000000000000;

    pub const deviceBase: usize = 0;

    pub const serialMmio = @intToPtr(*volatile u8, deviceBase + 0x09000000);
};
