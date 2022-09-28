const KernelAllocator = @import("memory.zig").KernelAllocator;
const utils = @import("utils.zig");
const kprint = @import("uart.zig").kprint;

pub fn reportKMemStatus(alloc: anytype) void {
    kprint("-------------- \n", .{});
    kprint("kmem: used {d} \n", .{alloc.kernel_mem_used});

    var chunks_used: usize = 0;
    for (alloc.chunks) |*chunk| {
        if (!chunk.free)
            chunks_used += 1;
    }
    kprint("chunks used: {d}\n", .{chunks_used});
    kprint("------------ \n", .{});
}
