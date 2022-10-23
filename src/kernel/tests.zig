const UserSpaceAllocator = @import("KernelAllocator.zig").UserSpaceAllocator;
const kprint = @import("periph").uart.UartWriter(.ttbr0).kprint;

pub fn testUserPageAlloc(alloc: anytype) !void {
    var p1 = try alloc.allocNPage(10);
    var p2 = try alloc.allocNPage(10);
    var p3 = try alloc.allocNPage(10);
    var p4 = try alloc.allocNPage(10);
    var p5 = try alloc.allocNPage(10);

    try alloc.freeNPage(p2, 10);
    var p6 = try alloc.allocNPage(10);

    try alloc.freeNPage(p1, 10);
    try alloc.freeNPage(p3, 10);
    try alloc.freeNPage(p4, 10);
    try alloc.freeNPage(p5, 10);

    try alloc.freeNPage(p6, 10);
    kprint("[kTEST] userspace page alloc test successfull \n", .{});
}

pub fn testUserSpaceMem(addr: usize) void {
    @intToPtr(*usize, addr).* = 100;
    if (@intToPtr(*usize, addr).* == 100)
        kprint("[kTEST] write to userspace successfull \n", .{});
}

pub fn testKMalloc(alloc: anytype) !void {
    var alloced_obj = try alloc.alloc(usize, 10, null);

    alloced_obj[1] = 100;
    alloced_obj[9] = 900;
    var alloced_obj2 = try alloc.alloc(usize, 102, null);
    try alloc.free(alloced_obj);
    alloced_obj2[33] = 3;
    try alloc.free(alloced_obj2);

    var alloced_obj3 = try alloc.alloc(u8, 102400 * 1.5, null);
    alloced_obj3[30] = 0xff;
    var alloced_obj4 = try alloc.alloc(u8, 102400 * 1.5, null);
    alloced_obj4[30] = 0xff;
    var alloced_obj5 = try alloc.alloc(u8, 102400 * 1.5, null);
    alloced_obj5[30] = 0xff;

    try alloc.free(alloced_obj4);

    var alloced_obj6 = try alloc.alloc(u8, 102400 * 1.5, null);
    alloced_obj6[30] = 0xff;

    try alloc.free(alloced_obj5);
    try alloc.free(alloced_obj3);
    try alloc.free(alloced_obj6);
    kprint("[kTEST] kernel alloc test successfull \n", .{});
}
