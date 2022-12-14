const std = @import("std");
const board = @import("board");
const AddrSpace = board.boardConfig.AddrSpace;

pub fn UartWriter(comptime addr_space: AddrSpace) type {
    const pl011 = @import("pl011.zig").Pl011(addr_space);
    return struct {
        const Self = @This();
        pub const Writer = std.io.Writer(*Self, error{}, appendWrite);

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }

        /// Same as `append` except it returns the number of bytes written, which is always the same
        /// as `m.len`. The purpose of this function existing is to match `std.io.Writer` API.
        fn appendWrite(self: *Self, data: []const u8) error{}!usize {
            _ = self;
            pl011.write(data);
            return data.len;
        }

        pub fn kprint(comptime print_string: []const u8, args: anytype) void {
            var tempW: UartWriter(addr_space) = undefined;
            std.fmt.format(tempW.writer(), print_string, args) catch |err| {
                @panic(err);
            };
        }
    };
}
