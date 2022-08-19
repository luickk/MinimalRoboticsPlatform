const addr = @import("raspberryAddr.zig").Timer;

var timerVal: u32 = 0;

pub fn initTimer() void {
    var cur_val: u32 = @intToPtr(*u32, addr.timerClo).*;
    cur_val += addr.Values.timerInterval;
    @intToPtr(*u32, addr.timerC1).* = cur_val;
}

pub fn handleTimerIrq() void {
    timerVal += addr.Values.timerInterval;
    @intToPtr(*u32, addr.timerC1).* = timerVal;
    @intToPtr(*u32, addr.timerCs).* = addr.Values.timerCsM1;
}
