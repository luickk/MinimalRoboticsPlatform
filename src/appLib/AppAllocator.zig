const std = @import("std");
const board = @import("board");
const alignForward = std.mem.alignForward;
const utils = @import("utils");

const appAllocatorChunkSize = 0x10000;

pub const AppAllocator = struct {
    const Error = error{ OutOfChunks, OutOfMem, AddrNotInMem, AddrNotValid, MemBaseNotAligned, NoHeapStartLabel };
    const maxChunks = @divExact(board.config.mem.app_vm_mem_size, appAllocatorChunkSize);

    mem_base: usize,
    kernel_mem: [maxChunks]bool,
    used_chunks: usize,

    pub fn init(mem_base: ?usize) !AppAllocator {
        var heap_start: usize = undefined;
        if (mem_base == null) {
            const _heap_start: usize = @intFromPtr(@extern(?*u8, .{ .name = "_heap_start" }) orelse return Error.NoHeapStartLabel);
            heap_start = _heap_start;
        } else heap_start = mem_base.?;
        if (heap_start % 8 != 0) return Error.MemBaseNotAligned;
        var ka = AppAllocator{
            .kernel_mem = [_]bool{false} ** maxChunks,
            // can currently only increase and indicates at which point findFree() is required
            .used_chunks = 0,
            .mem_base = heap_start,
        };
        return ka;
    }

    pub fn alloc(self: *AppAllocator, comptime T: type, n: usize, alignment: ?usize) ![]T {
        var alignm: usize = @alignOf(T);
        if (alignment) |a| alignm = a;

        var size = @sizeOf(T) * n;
        var req_chunks = try std.math.divCeil(usize, size, appAllocatorChunkSize);

        if (try self.findFree(self.used_chunks, size)) |free_mem_first_chunk| {
            for (self.kernel_mem[free_mem_first_chunk .. free_mem_first_chunk + req_chunks]) |*chunk| {
                chunk.* = true;
            }
            var alloc_addr = self.mem_base + (free_mem_first_chunk * appAllocatorChunkSize);
            var aligned_alloc_slice = @as([*]T, @ptrFromInt(alignForward(usize, alloc_addr, alignm)));
            return aligned_alloc_slice[0 .. n - 1];
        } else if (self.used_chunks + req_chunks > maxChunks) {
            return Error.OutOfMem;
        }

        var first_chunk = self.used_chunks;
        var last_chunk = self.used_chunks + req_chunks;
        self.used_chunks += req_chunks;
        for (self.kernel_mem[first_chunk..last_chunk]) |*chunk| {
            chunk.* = true;
        }
        var alloc_addr = self.mem_base + (first_chunk * appAllocatorChunkSize);
        var aligned_alloc_slice = @as([*]T, @ptrFromInt(alignForward(usize, alloc_addr, alignm)));
        return aligned_alloc_slice[0 .. n - 1];
    }

    /// finds continous free memory in fragmented kernel memory; marks returned memory as not free!
    pub fn findFree(self: *AppAllocator, to_chunk: usize, req_size: usize) !?usize {
        var continous_chunks: usize = 0;
        var req_chunks = (try std.math.divCeil(usize, req_size, appAllocatorChunkSize));
        for (self.kernel_mem, 0..) |chunk, i| {
            if (i >= to_chunk) {
                return null;
            }
            if (!chunk) {
                continous_chunks += 1;
            } else {
                continous_chunks = 0;
            }
            if (continous_chunks >= req_chunks) {
                var first_chunk = i;
                if (i > 0) first_chunk -= req_chunks;

                return first_chunk;
            }
        }
        return null;
    }

    pub fn free(self: *AppAllocator, to_free: anytype) !void {
        const Slice = @typeInfo(@TypeOf(to_free)).Pointer;
        const byte_slice = std.mem.sliceAsBytes(to_free);
        const size = byte_slice.len + if (Slice.sentinel != null) @sizeOf(Slice.child) else 0;
        if (size == 0) return;

        // compensating for alignment
        var addr_unaligned = @intFromPtr(byte_slice.ptr);
        if (addr_unaligned == self.mem_base) addr_unaligned -= (try std.math.mod(usize, @intFromPtr(byte_slice.ptr), appAllocatorChunkSize));
        if (addr_unaligned > (self.mem_base + (maxChunks * appAllocatorChunkSize)))
            return Error.AddrNotInMem;

        var i_chunk_to_free: usize = (try std.math.divCeil(usize, std.math.sub(usize, addr_unaligned, self.mem_base) catch {
            return Error.AddrNotInMem;
        }, appAllocatorChunkSize)) - 1;

        var n_chunks_to_free: usize = try std.math.divCeil(usize, size, appAllocatorChunkSize);
        for (self.kernel_mem[i_chunk_to_free .. i_chunk_to_free + n_chunks_to_free]) |*chunk| {
            chunk.* = false;
        }
    }
};
