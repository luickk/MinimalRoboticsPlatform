const CpuContext = @import("arm").cpuContext.CpuContext;
const kprint = @import("periph").uart.UartWriter(.ttbr1).kprint;
const sharedKServices = @import("sharedKServices");
const Scheduler = sharedKServices.Scheduler;
const timerCfg = @import("board").PeriphConfig(.ttbr1).Timer;

var timerVal: u32 = 0;

extern var scheduler: *Scheduler;

const ic_base_address = @import("board").PeriphConfig(.ttbr1).InterruptController.base_address;

pub const RegMap = struct {
    pub const timerCs = @intToPtr(*volatile u32, timerCfg.base_address + 0x0);
    pub const timerLo = @intToPtr(*volatile u32, timerCfg.base_address + 0x4);
    pub const timerHi = @intToPtr(*volatile u32, timerCfg.base_address + 0x8);
    pub const timerC0 = @intToPtr(*volatile u32, timerCfg.base_address + 0xc);
    pub const timerC1 = @intToPtr(*volatile u32, timerCfg.base_address + 0x10);
    pub const timerClo = @intToPtr(*volatile u32, timerCfg.base_address + 0x4);
};

// address values
pub const RegValues = struct {
    pub const timerInterval: u32 = 100000;
    pub const timerCsM0: u32 = 1 << 0;
    pub const timerCsM1: u32 = 1 << 1;
    pub const timerCsM2: u32 = 1 << 2;
    pub const timerCsM3: u32 = 1 << 3;
};

pub fn initTimer() void {
    timerVal = RegMap.timerLo.*;
    timerVal += RegValues.timerInterval;
    RegMap.timerC1.* = timerVal;
}

pub fn handleTimerIrq(irq_context: *CpuContext) void {
    timerVal += RegValues.timerInterval;
    RegMap.timerC1.* = timerVal;
    RegMap.timerCs.* = RegMap.timerCs.* | RegValues.timerCsM1;

    @intToPtr(*volatile u32, ic_base_address + 0x10).* = 1 << 1;

    scheduler.timerIntEvent(irq_context);
}
