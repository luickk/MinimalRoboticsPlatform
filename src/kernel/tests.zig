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
    kprint("{any} \n", .{alloc.kernel_mem});
    var alloced_obj = try alloc.alloc(usize, 10);
    kprint("{any} \n", .{alloc.kernel_mem});
    alloced_obj[1] = 100;
    alloced_obj[9] = 900;
    try alloc.free(alloced_obj);
    kprint("{any} \n", .{alloc.kernel_mem});

    kprint("[kTEST] kernel alloc test successfull \n", .{});
}
