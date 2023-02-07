const std = @import("std");

// todo => seconds to ticks
pub inline fn wait(delay_in_ticks: usize) void {
    // const delay_ticks = utils.calcTicksFromHertz(kernelTimer.getTimerFreqInHertz(), delay_in_nano_secs);
    asm volatile (
        \\mov x0, %[delay]
        \\delay_loop:
        \\subs x0, x0, #1
        \\bne delay_loop
        :
        : [delay] "r" (delay_in_ticks),
        : "x0"
    );
}
