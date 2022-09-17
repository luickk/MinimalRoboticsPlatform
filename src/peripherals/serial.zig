const std = @import("std");
const board = @import("board");
const mmu = @import("mmu.zig");

pub const SerialKernelWriter = struct {
    pub const Writer = std.io.Writer(*SerialKernelWriter, error{}, appendWrite);

    pub fn writer(self: *SerialKernelWriter) Writer {
        return .{ .context = self };
    }

    /// Same as `append` except it returns the number of bytes written, which is always the same
    /// as `m.len`. The purpose of this function existing is to match `std.io.Writer` API.
    fn appendWrite(self: *SerialKernelWriter, data: []const u8) error{}!usize {
        _ = self;
        for (data) |ch| {
            var sec_addr = mmu.toSecure(*volatile u8, board.Addresses.serialMmio);
            sec_addr.* = ch;
            // board.serialMmio.* = ch;
        }
        return data.len;
    }
};

pub fn kprint(comptime print_string: []const u8, args: anytype) void {
    var tempW: SerialKernelWriter = undefined;
    std.fmt.format(tempW.writer(), print_string, args) catch |err| {
        @panic(err);
    };
}

pub const SerialBlWriter = struct {
    pub const Writer = std.io.Writer(*SerialBlWriter, error{}, appendWrite);

    pub fn writer(self: *SerialBlWriter) Writer {
        return .{ .context = self };
    }

    /// Same as `append` except it returns the number of bytes written, which is always the same
    /// as `m.len`. The purpose of this function existing is to match `std.io.Writer` API.
    fn appendWrite(self: *SerialBlWriter, data: []const u8) error{}!usize {
        _ = self;
        for (data) |ch| {
            board.Addresses.serialMmio.* = ch;
        }
        return data.len;
    }
};

pub fn bprint(comptime print_string: []const u8, args: anytype) void {
    var tempW: SerialBlWriter = undefined;
    std.fmt.format(tempW.writer(), print_string, args) catch |err| {
        @panic(err);
    };
}
