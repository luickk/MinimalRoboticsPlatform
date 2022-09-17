const mmu = @import("peripherals").mmu;

pub const RamMemLayout = struct {
    kernel_space_mapping: mmu.Mapping,

    user_space_mapping: mmu.Mapping,
};

pub const BoardMemLayout = struct {
    rom_start_addr: usize,
    rom_len: usize,

    ram_start_addr: usize,
    ram_len: usize,
    ram_layout: RamMemLayout,

    storage_start_addr: usize,
    storage_len: usize,
};

pub const BoardParams = struct {
    board_name: []const u8,
    mem: BoardMemLayout,
    qemu_launch_command: []const []const u8,
};
