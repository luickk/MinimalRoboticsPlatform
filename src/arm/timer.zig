const timerAddr = @import("board").PeriphConfig(true).Timer;

var timerVal: u32 = 0;

pub const RegMap = struct {
    pub const timerCs = @intToPtr(*u32, timerAddr.base_address + 0x0);
    pub const timerC1 = @intToPtr(*u32, timerAddr.base_address + 0x10);
    pub const timerClo = @intToPtr(*u32, timerAddr.base_address + 0x4);
};

// address values
pub const RegValues = struct {
    pub const timerInterval: u32 = 200000;
    pub const timerCsM0: u32 = 1 << 0;
    pub const timerCsM1: u32 = 1 << 1;
    pub const timerCsM2: u32 = 1 << 2;
    pub const timerCsM3: u32 = 1 << 3;
};

pub fn initTimer() void {
    var cur_val: u32 = RegMap.timerClo.*;
    cur_val += RegValues.timerInterval;
    RegMap.timerC1.* = cur_val;
}

pub fn handleTimerIrq() void {
    timerVal += RegValues.timerInterval;
    RegMap.timerC1.* = timerVal;
    RegMap.timerCs.* = RegValues.timerCsM1;
}
