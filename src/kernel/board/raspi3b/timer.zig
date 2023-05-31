const CpuContext = @import("arm").cpuContext.CpuContext;
const kprint = @import("periph").uart.UartWriter(.ttbr1).kprint;
const sharedKernelServices = @import("sharedKernelServices");
const Scheduler = sharedKernelServices.Scheduler;
const board = @import("board");
const timerCfg = board.PeriphConfig(.ttbr1).Timer;
const utils = @import("utils");

var timerVal: u32 = 0;

// global user required since timer is handleTimerIrq is called from the exception vector table
extern var scheduler: *Scheduler;

// raspberry 3b available timers: system timer (this one), arm timer, free runnning timer
// raspberry system timer frequency is 1 Mhz
var cnt_freq: u32 = 1000000;

const ticks = @truncate(u32, try utils.calcTicksFromHertz(cnt_freq, board.config.scheduler_freq_in_hertz));

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

pub fn initTimer() !void {
    timerVal = RegMap.timerLo.*;
    timerVal += @truncate(u32, try utils.calcTicksFromHertz(cnt_freq, board.config.scheduler_freq_in_hertz));
    RegMap.timerC1.* = timerVal;
}

// the qemu system timer is weird. It only triggers an interrupt if timerC1 is == timerLo instead of timerC1 is <= timerLo.
// Qemu devs stated that this is intended and what the documentation is saying, but are also doubting that this is the physical bcm2835 implementation
pub fn handleTimerIrq(irq_context: *CpuContext) !void {
    timerVal = RegMap.timerLo.*;
    if (@addWithOverflow(u32, timerVal, ticks, &timerVal)) {
        timerVal = RegMap.timerLo.*;
        timerVal += @truncate(u32, try utils.calcTicksFromHertz(cnt_freq, board.config.scheduler_freq_in_hertz));
    }

    RegMap.timerC1.* = timerVal;
    RegMap.timerCs.* = RegMap.timerCs.* | RegValues.timerCsM1;
    // print("benis \n");
    scheduler.timerIntEvent(irq_context);
}
