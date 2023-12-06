const kprint = @import("periph").uart.UartWriter(.ttbr1).kprint;

pub fn testUserPageAlloc(alloc: anytype) !void {
    const p1 = try alloc.allocNPage(10);
    const p2 = try alloc.allocNPage(10);
    const p3 = try alloc.allocNPage(10);
    const p4 = try alloc.allocNPage(10);
    @as(*volatile u8, @ptrCast(p1)).* = 10;
    @as(*volatile u8, @ptrCast(p2)).* = 10;
    @as(*volatile u8, @ptrCast(p3)).* = 10;
    @as(*volatile u8, @ptrCast(p4)).* = 10;

    const p5 = try alloc.allocNPage(10);
    @as(*volatile u8, @ptrCast(p5)).* = 10;

    try alloc.freeNPage(p2, 10);
    const p6 = try alloc.allocNPage(10);

    try alloc.freeNPage(p1, 10);
    try alloc.freeNPage(p3, 10);
    try alloc.freeNPage(p4, 10);
    try alloc.freeNPage(p5, 10);

    try alloc.freeNPage(p6, 10);
    kprint("[kTEST] userspace page alloc test successfull \n", .{});
}

pub fn testUserSpaceMem(addr: usize) void {
    @as(*usize, @ptrFromInt(addr)).* = 100;
    if (@as(*usize, @ptrFromInt(addr)).* == 100)
        kprint("[kTEST] write to userspace successfull \n", .{});
}

pub fn testKMalloc(alloc: anytype) !void {
    const alloced_obj = try alloc.alloc(usize, 10, null);

    alloced_obj[1] = 100;
    alloced_obj[9] = 900;
    const alloced_obj2 = try alloc.alloc(usize, 102, null);
    try alloc.free(alloced_obj);
    alloced_obj2[33] = 3;
    try alloc.free(alloced_obj2);

    const alloced_obj3 = try alloc.alloc(u8, 102400 * 1.5, null);
    alloced_obj3[30] = 0xff;
    const alloced_obj4 = try alloc.alloc(u8, 102400 * 1.5, null);
    alloced_obj4[30] = 0xff;
    const alloced_obj5 = try alloc.alloc(u8, 102400 * 1.5, null);
    alloced_obj5[30] = 0xff;

    try alloc.free(alloced_obj4);

    const alloced_obj6 = try alloc.alloc(u8, 102400 * 1.5, null);
    alloced_obj6[30] = 0xff;

    try alloc.free(alloced_obj5);
    try alloc.free(alloced_obj3);
    try alloc.free(alloced_obj6);
    kprint("[kTEST] kernel alloc test successfull \n", .{});
}
