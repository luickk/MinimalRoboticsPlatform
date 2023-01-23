const std = @import("std");

pub fn ceilRoundToMultiple(inp: usize, multiple: usize) !usize {
    return inp + (multiple - (try std.math.mod(usize, inp, multiple)));
}

pub fn calcTicksFromSeconds(timer_freq_in_hertz: usize, seconds: f64) usize {
    return @floatToInt(usize, @intToFloat(f64, timer_freq_in_hertz) * seconds);
}

pub fn calcTicksFromNanoSeconds(timer_freq_in_hertz: usize, nano_seconds: usize) usize {
    const freq_in_nano_hertz = @intToFloat(f64, timer_freq_in_hertz) / @intToFloat(f64, 1000000000);
    return @floatToInt(usize, freq_in_nano_hertz * @intToFloat(f64, nano_seconds));
}
