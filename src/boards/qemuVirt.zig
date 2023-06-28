pub const boardConfig = @import("boardConfig.zig");
const kpi = @import("kpi");

const timerDriver = @import("timerDriver");const genericTimer = timerDriver.genericTimer;

// mmu starts at lvl1 for which 0xFFFFFF8000000000 is the lowest possible va
const vaStart: usize = 0xFFFFFF8000000000;
pub const config = boardConfig.BoardConfig{
    .board = .qemuVirt,
    .mem = boardConfig.BoardConfig.BoardMemLayout{
        .va_start = vaStart,

        .bl_stack_size = 0x10000,
        .k_stack_size = 0x10000,
        .app_stack_size = 0x20000,
        .app_vm_mem_size = 0x1000000,

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

        .va_kernel_space_gran = boardConfig.Granule.Fourk,
        .va_kernel_space_page_table_capacity = 0x40000000,
        .va_user_space_gran = boardConfig.Granule.Fourk,
        .va_user_space_page_table_capacity = 0x40000000,

        .storage_start_addr = 0,
        .storage_size = 0,
    },
    // null means that the value is not known at compile time but has to be read from a reg or periph
    .timer_freq_in_hertz = null,
    .scheduler_freq_in_hertz = 250,
};


pub const GenericTimerType = genericTimer.GenericTimer(null, config.scheduler_freq_in_hertz);
var genericTimerInst = GenericTimerType.init();
pub const GenericTimerKpiType = kpi.TimerKpi(*GenericTimerType, GenericTimerType.Error, GenericTimerType.setupGt, GenericTimerType.timerInt, GenericTimerType.timer_name);

pub const driver = boardConfig.Driver(GenericTimerKpiType, null) {
    .timerDriver = GenericTimerKpiType.init(&genericTimerInst),
    .secondaryInterruptConrtollerDriver = null,
};

pub fn PeriphConfig(comptime addr_space: boardConfig.AddrSpace) type {
    const new_ttbr1_device_base_ = 0x30000000;
    comptime var device_base_mapping_bare: usize = 0x8000000;

    // in ttbr1 all periph base is mapped to 0x40000000
    if (addr_space.isKernelSpace()) device_base_mapping_bare = config.mem.va_start + new_ttbr1_device_base_;

    return struct {
        pub const device_base_size: usize = 0xA000000;
        pub const device_base: usize = device_base_mapping_bare;
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
        };
    };
}
