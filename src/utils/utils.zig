const std = @import("std");
const board = @import("board");

pub const Error = error{
    SchedulerFreqTooLow,
};

pub fn calcTicksFromHertz(timer_freq_in_hertz: usize, wanted_freq_in_hertz: usize) !usize {
    

    if (wanted_freq_in_hertz > timer_freq_in_hertz) return Error.SchedulerFreqTooLow;
    return (try std.math.divTrunc(usize, timer_freq_in_hertz, wanted_freq_in_hertz));
}

pub fn calcTicksFromNanoSeconds(timer_freq_in_hertz: usize, nano_seconds: usize) usize {
    const freq_in_nano_hertz = @intToFloat(f64, timer_freq_in_hertz) / @intToFloat(f64, 1000000000);
    return @floatToInt(usize, freq_in_nano_hertz * @intToFloat(f64, nano_seconds));
}

pub inline fn toTtbr1(comptime T: type, inp: T) T {
    switch (@typeInfo(T)) {
        .Pointer => {
            return @intToPtr(T, @ptrToInt(inp) | board.config.mem.va_start);
        },
        .Int => {
            return inp | board.config.mem.va_start;
        },
        else => @compileError("mmu address translation: not supported type"),
    }
}

pub inline fn toTtbr0(comptime T: type, inp: T) T {
    switch (@typeInfo(T)) {
        .Pointer => {
            return @intToPtr(T, @ptrToInt(inp) & ~(board.config.mem.va_start));
        },
        .Int => {
            return inp & ~(board.config.mem.va_start);
        },
        else => @compileError("mmu address translation: not supported type"),
    }
}
