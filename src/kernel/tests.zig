const UserSpaceAllocator = @import("memory.zig").UserSpaceAllocator;
const kprint = @import("peripherals").serial.kprint;

pub fn testKMalloc(alloc: anytype) !void {
    var p1 = try alloc.allocNPage(10);
    var p2 = try alloc.allocNPage(10);
    var p3 = try alloc.allocNPage(10);
    var p4 = try alloc.allocNPage(10);
    var p5 = try alloc.allocNPage(10);

    try alloc.freeNPage(p2, 10);
    var p6 = try alloc.allocNPage(10);

    // kprint("Pages alloced: {d}, {d}, {d}, {d}, {d}, {d} \n", .{ @ptrToInt(p1), @ptrToInt(p2), @ptrToInt(p3), @ptrToInt(p4), @ptrToInt(p5), @ptrToInt(p6) });

    try alloc.freeNPage(p1, 10);
    try alloc.freeNPage(p3, 10);
    try alloc.freeNPage(p4, 10);
    try alloc.freeNPage(p5, 10);
    try alloc.freeNPage(p6, 10);
    kprint("[kTEST] userspace page alloc test successfull \n", .{});
}

pub fn testUserSpaceMem() void {
    @intToPtr(*usize, 0x10000000).* = 100;
    if (@intToPtr(*usize, 0x10000000).* == 100)
        kprint("[kTEST] write to userspace successfull \n", .{});
}
