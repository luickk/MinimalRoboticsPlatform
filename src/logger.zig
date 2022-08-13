const KernelAllocator = @import("memory.zig").KernelAllocator;
const utils = @import("utils.zig");
const kprint = @import("serial.zig").kprint;

pub fn reportKMemStatus(alloc: anytype) void {
    kprint("-------------- \n", .{});
    kprint("kmem: used {d}, pages used: {d} \n", .{ alloc.kernel_mem_used, alloc.used_pages });

    var chunks_used: usize = 0;
    for (alloc.pages) |*page, p_i| {
        for (page.chunks) |*chunk| {
            if (!chunk.free)
                chunks_used += 1;
        }
        if (chunks_used != 0)
            kprint("chunks used page({d}): {d}\n", .{ p_i, chunks_used });
        chunks_used = 0;
    }
    kprint("------------ \n", .{});
}
