const std = @import("std");
const board = @import("board");

pub fn calcTicksFromHertz(timer_freq_in_hertz: usize, wanted_freq_in_hertz: usize) !usize {
    const Error = error{
        SchedulerFreqTooLow,
    };

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

pub const CircBuff = struct {
    const Error = error{
        BuffOutOfStorage,
    };
    buff: []u8,
    curr_read_ptr: usize,
    curr_write_ptr: usize,

    pub fn init(buff_addr: usize, buff_len: usize) CircBuff {
        var buff: []u8 = undefined;
        buff.ptr = @intToPtr([*]u8, buff_addr);
        buff.len = buff_len;

        return .{ .buff = buff, .curr_read_ptr = 0, .curr_write_ptr = 0 };
    }
    pub fn write(self: *CircBuff, data: []u8) !void {
        if (self.curr_write_ptr + data.len > self.buff.len) return Error.BuffOutOfStorage;
        std.mem.copy(u8, self.buff[self.curr_write_ptr..], data);
        self.curr_write_ptr += data.len;
    }

    pub fn read(self: *CircBuff, len: usize) ![]u8 {
        if (self.curr_read_ptr - len < 0) return Error.BuffOutOfStorage;
        var res = self.buff[self.curr_read_ptr - len .. self.curr_read_ptr];
        self.curr_read_ptr -= len;
        return res;
    }
};
