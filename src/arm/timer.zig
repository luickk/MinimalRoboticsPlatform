const timerAddr = @import("board").Addresses.Timer;

var timerVal: u32 = 0;

pub fn initTimer() void {
    var cur_val: u32 = @intToPtr(*u32, timerAddr.timerClo).*;
    cur_val += timerAddr.Values.timerInterval;
    @intToPtr(*u32, timerAddr.timerC1).* = cur_val;
}

pub fn handleTimerIrq() void {
    timerVal += timerAddr.Values.timerInterval;
    @intToPtr(*u32, timerAddr.timerC1).* = timerVal;
    @intToPtr(*u32, timerAddr.timerCs).* = timerAddr.Values.timerCsM1;
}
