const std = @import("std");
const alignForward = std.mem.alignForward;
const utils = @import("utils");
const maxChunks = 10000;

pub const AppAllocator = struct {
    const Error = error{
        OutOfChunks,
        OutOfMem,
        AddrNotInMem,
        AddrNotValid,
        MemBaseNotAligned,
    };

    mem_base: usize,
    kernel_mem: [maxChunks]bool,
    chunk_size: usize,
    used_chunks: usize,

    pub fn init(mem_base: usize, mem_size: usize, chunk_size: usize) !AppAllocator {
        const req_chunks = try std.math.divCeil(usize, mem_size, chunk_size);
        if (req_chunks > maxChunks) return Error.OutOfChunks;
        if (mem_base % 8 != 0) return Error.MemBaseNotAligned;
        var ka = AppAllocator{
            .kernel_mem = [_]bool{false} ** maxChunks,
            // can currently only increase and indicates at which point findFree() is required
            .used_chunks = 0,
            .chunk_size = chunk_size,
            .mem_base = mem_base,
        };
        return ka;
    }

    pub fn alloc(self: *AppAllocator, comptime T: type, n: usize, alignment: ?usize) ![]T {
        var alignm: usize = @alignOf(T);
        if (alignment) |a| alignm = a;

        var size = @sizeOf(T) * n;
        var req_chunks = try std.math.divCeil(usize, size, self.chunk_size);

        if (try self.findFree(self.used_chunks, size)) |free_mem_first_chunk| {
            for (self.kernel_mem[free_mem_first_chunk .. free_mem_first_chunk + req_chunks]) |*chunk| {
                chunk.* = true;
            }
            var alloc_addr = self.mem_base + (free_mem_first_chunk * self.chunk_size);
            var aligned_alloc_slice = @intToPtr([*]T, alignForward(alloc_addr, alignm));
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
        var alloc_addr = self.mem_base + (first_chunk * self.chunk_size);
        var aligned_alloc_slice = @intToPtr([*]T, alignForward(alloc_addr, alignm));
        return aligned_alloc_slice[0 .. n - 1];
    }

    /// finds continous free memory in fragmented kernel memory; marks returned memory as not free!
    pub fn findFree(self: *AppAllocator, to_chunk: usize, req_size: usize) !?usize {
        var continous_chunks: usize = 0;
        var req_chunks = (try std.math.divCeil(usize, req_size, self.chunk_size));
        for (self.kernel_mem) |chunk, i| {
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
        var addr_unaligned = @ptrToInt(byte_slice.ptr);
        if (addr_unaligned == self.mem_base) addr_unaligned -= (try std.math.mod(usize, @ptrToInt(byte_slice.ptr), self.chunk_size));
        if (addr_unaligned > (self.mem_base + (maxChunks * self.chunk_size)))
            return Error.AddrNotInMem;

        var i_chunk_to_free: usize = (try std.math.divCeil(usize, std.math.sub(usize, addr_unaligned, self.mem_base) catch {
            return Error.AddrNotInMem;
        }, self.chunk_size)) - 1;

        var n_chunks_to_free: usize = try std.math.divCeil(usize, size, self.chunk_size);
        for (self.kernel_mem[i_chunk_to_free .. i_chunk_to_free + n_chunks_to_free]) |*chunk| {
            chunk.* = false;
        }
    }
};
