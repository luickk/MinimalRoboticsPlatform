const std = @import("std");
const board = @import("board");

pub const Error = error{
    SchedulerFreqTooLow,
};

pub fn calcTicksFromHertz(timer_freq_in_hertz: usize, wanted_freq_in_hertz: usize) usize {
    // todo => restore line below
    // if (wanted_freq_in_hertz > timer_freq_in_hertz) return Error.SchedulerFreqTooLow;
    // todo => use std divtrunct not /
    return timer_freq_in_hertz / wanted_freq_in_hertz;
}

pub inline fn toTtbr1(comptime T: type, inp: T) T {
    switch (@typeInfo(T)) {
        .Pointer => {
            return @as(T, @ptrFromInt(@intFromPtr(inp) | board.config.mem.va_start));
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
            return @as(T, @ptrFromInt(@intFromPtr(inp) & ~(board.config.mem.va_start)));
        },
        .Int => {
            return inp & ~(board.config.mem.va_start);
        },
        else => @compileError("mmu address translation: not supported type"),
    }
}
