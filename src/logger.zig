const KernelAllocator = @import("memory.zig").KernelAllocator;
const utils = @import("utils.zig");
const kprint = @import("serial.zig").kprint;

pub fn reportKMemStatus(alloc: anytype) void {
    kprint("-------------- \n", .{});
    kprint("kmem: used {d}, pages used: {d} \n", .{ alloc.kernel_mem_used, alloc.used_pages });

    var chunks_used: usize = 0;
    for (page.chunks) |*chunk| {
        if (!chunk.free)
            chunks_used += 1;
    }
    kprint("chunks used: {d}\n", .{chunks_used});
    kprint("------------ \n", .{});
}
