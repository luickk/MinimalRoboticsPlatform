const KernelAllocator = @import("memory.zig").KernelAllocator;
const kprint = @import("serial.zig").kprint;

pub fn reportKMemStatus(alloc: anytype) void {
    kprint("-------------- \n", .{});
    kprint("kmem: used {d}, pages used: {d}, allocs used: {d} \n", .{ alloc.kernel_mem_used, alloc.used_pages, alloc.used_allocs });
    kprint("chunks used per Page: \n", .{});
    for (alloc.pages) |*page, i| {
        kprint("{d}: {d} \n", .{ i, page.used_chunks });
    }
    kprint("------------ \n", .{});
}
