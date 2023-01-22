const CpuContext = @import("arm").cpuContext.CpuContext;
const kprint = @import("periph").uart.UartWriter(.ttbr1).kprint;
const sharedKernelServices = @import("sharedKernelServices");
const Scheduler = sharedKernelServices.Scheduler;
const timerCfg = @import("board").PeriphConfig(.ttbr1).Timer;

var timerVal: u32 = 0;
extern var scheduler: *Scheduler;

// raspberry 3b available timers: system timer (this one), arm timer, free runnning timer
// raspberry system timer frequency is 1 Mhz
var cnt_freq: u32 = 1000000;
// 0.002 is the highest possible frequency
var freq_factor: f32 = 0.09;

// todo => handle timer overflow

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
    // System Timer Controll State irq clear vals
    pub const timerCsM0: u32 = 1 << 0;
    pub const timerCsM1: u32 = 1 << 1;
    pub const timerCsM2: u32 = 1 << 2;
    pub const timerCsM3: u32 = 1 << 3;
};

pub fn initTimer() void {
    timerVal = RegMap.timerLo.*;
    timerVal += @floatToInt(u32, @intToFloat(f64, cnt_freq) * freq_factor);
    RegMap.timerC1.* = timerVal;
}

pub fn handleTimerIrq(irq_context: *CpuContext) void {
    timerVal += @floatToInt(u32, @intToFloat(f64, cnt_freq) * freq_factor);
    RegMap.timerC1.* = timerVal;
    RegMap.timerCs.* = RegMap.timerCs.* | RegValues.timerCsM1;
    scheduler.timerIntEvent(irq_context);
}
