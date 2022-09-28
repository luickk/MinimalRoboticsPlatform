const timerAddr = @import("board").PeriphConfig(true).Timer;

var timerVal: u32 = 0;

// address values
pub const RegValues = struct {
    pub const timerInterval: u32 = 200000;
    pub const timerCsM0: u32 = 1 << 0;
    pub const timerCsM1: u32 = 1 << 1;
    pub const timerCsM2: u32 = 1 << 2;
    pub const timerCsM3: u32 = 1 << 3;
};

pub fn initTimer() void {
    var cur_val: u32 = @intToPtr(*u32, timerAddr.timerClo).*;
    cur_val += RegValues.timerInterval;
    @intToPtr(*u32, timerAddr.timerC1).* = cur_val;
}

pub fn handleTimerIrq() void {
    timerVal += RegValues.timerInterval;
    @intToPtr(*u32, timerAddr.timerC1).* = timerVal;
    @intToPtr(*u32, timerAddr.timerCs).* = RegValues.timerCsM1;
}
