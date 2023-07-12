pub const boardConfig = @import("configTemplates").boardConfigTemplate;
const kpi = @import("kpi");

const timerDriver = @import("timerDriver");
const bcm2835Timer = timerDriver.bcm2835Timer;
const genericTimer = timerDriver.genericTimer;
const bcm2835IntController = @import("interruptControllerDriver").bcm2835InterruptController;

// mmu starts at lvl1 for which 0xFFFFFF8000000000 is the lowest possible va
const vaStart: usize = 0xFFFFFF8000000000;


pub const config = boardConfig.BoardConfig {
    .board_name = "raspi3b",
    .mem = .{
        .va_start = vaStart,
        .bl_stack_size = 0x10000,
        .k_stack_size = 0x10000,
        .app_stack_size = 0x20000,
        .app_vm_mem_size = 0x1000000,

        .rom_size = null,
        .bl_load_addr = 0x80000,

        // the raspberries addressable memory is all ram
        .ram_start_addr = 0,
        // the ram_size needs to be greater or equal to: kernel_space_size + user_space_size + (bl_load_addr or rom_size)
        .ram_size = 0x40000000,
        
        .kernel_space_size = 0x20000000,
        .user_space_size = 0x20000000,

        // has to be Fourk since without a rom the kernel is positioned at a (addr % 2mb) != 0, so a 4kb granule is required
        .va_kernel_space_gran = boardConfig.Granule.Fourk,
        .va_kernel_space_page_table_capacity = 0x40000000,

        .va_user_space_gran = boardConfig.Granule.Fourk,
        .va_user_space_page_table_capacity = 0x40000000,

        .storage_start_addr = 0,
        .storage_size = 0,
    },
    .static_memory_reserves = boardConfig.BoardConfig.StaticMemoryReserves{
        .ksemaphore_max_process_in_queue = 1000,
        .semaphore_max_process_in_queue = 1000,
        .mutex_max_process_in_queue = 1000,
        .topics_max_process_in_queue = 1000,    
    },
    .scheduler_freq_in_hertz = 250,
};

// --- driver ---
pub const GenericTimerType = genericTimer.GenericTimer(null, config.scheduler_freq_in_hertz);
var genericTimerInst = GenericTimerType.init();

pub const Bcm2835TimerType = bcm2835Timer.Bcm2835Timer(PeriphConfig(.ttbr1).Timer.base_address, config.scheduler_freq_in_hertz);
var bcm2835TimerInst = Bcm2835TimerType.init();

pub const GenericTimerKpiType = kpi.TimerKpi(*GenericTimerType, GenericTimerType.Error, GenericTimerType.setupGt, GenericTimerType.timerInt, GenericTimerType.timer_name);
pub const Bcm2835TimerKpiType = kpi.TimerKpi(*Bcm2835TimerType, Bcm2835TimerType.Error, Bcm2835TimerType.initTimer, Bcm2835TimerType.handleTimerIrq, Bcm2835TimerType.timer_name);


// interrupt controller
const Bcm2835InterruptControllerType = bcm2835IntController.InterruptController(PeriphConfig(.ttbr1).InterruptController.base_address);
pub const SecondaryInterruptControllerKpiType = kpi.SecondaryInterruptControllerKpi(*Bcm2835InterruptControllerType, Bcm2835InterruptControllerType.Error, Bcm2835InterruptControllerType.initIc, Bcm2835InterruptControllerType.addIcHandler, Bcm2835InterruptControllerType.RegMap);
var secondaryInterruptControllerInst = Bcm2835InterruptControllerType.init();

pub const driver = boardConfig.Driver(GenericTimerKpiType, SecondaryInterruptControllerKpiType) {
    .timerDriver = GenericTimerKpiType.init(&genericTimerInst),
    // .timerDriver = Bcm2835TimerKpiType.init(&bcm2835TimerInst),
    .secondaryInterruptConrtollerDriver = SecondaryInterruptControllerKpiType.init(&secondaryInterruptControllerInst),
};

// -- driver --

pub fn PeriphConfig(comptime addr_space: boardConfig.AddrSpace) type {
    const new_ttbr1_device_base_ = 0x30000000;
    const device_base_mapping_bare: usize = 0x3f000000;
    comptime var device_base_mapping_new: usize = undefined;

    if (addr_space.isKernelSpace()) {
        device_base_mapping_new = config.mem.va_start + new_ttbr1_device_base_;
    } else device_base_mapping_new = device_base_mapping_bare;

    return struct {
        pub const device_base_size: usize = 0xA000000;
        pub const new_ttbr1_device_base: usize = new_ttbr1_device_base_;
        pub const device_base: usize = device_base_mapping_new;

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
            pub const base_address: usize = device_base + 0x00003000;
        };

        pub const ArmGenericTimer = struct {
            pub const base_address: usize = device_base + 0x1000040;
        };

        pub const InterruptController = struct {
            pub const base_address: usize = device_base + 0x0000b200;
        };
        
        pub const GicV2 = struct {
            pub const base_address: u64 = device_base + 0;
        };
    };
}
