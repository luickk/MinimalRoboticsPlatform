const std = @import("std");
const periph = @import("peripherals");
const utils = @import("utils");
const arm = @import("arm");

const kprint = periph.serial.kprint;
const addr = periph.rbAddr;
const mmu = arm.mmu;

// simply keeps record of what is kept where, slow but safe
pub fn KernelAllocator(comptime mem_size: usize, comptime chunk_size: usize) type {
    const max_chunks = try std.math.divTrunc(usize, mem_size, chunk_size);

    return struct {
        const Self = @This();
        const Error = error{
            OutOfMem,
            AddrNotInMem,
            AddrNotValid,
        };

        mem_base: usize,
        kernel_mem: [max_chunks]bool,
        used_chunks: usize,

        pub fn init(mem_base: usize) Self {
            var ka = Self{
                .kernel_mem = [_]bool{false} ** max_chunks,
                // can currently only increase and indicates at which point findFree() is required
                .used_chunks = 0,
                .mem_base = mem_base,
            };
            return ka;
        }

        pub fn alloc(self: *Self, comptime T: type, n: usize) ![]T {
            var size = @sizeOf(T) * n;
            var req_chunks = try std.math.divCeil(usize, size, chunk_size);
            if (self.used_chunks + req_chunks > max_chunks) {
                if (try self.findFree(self.used_chunks, size)) |free_mem_first_chunk| {
                    for (self.kernel_mem[free_mem_first_chunk .. free_mem_first_chunk + req_chunks]) |*chunk| {
                        chunk.* = true;
                    }
                    var alloc_addr = self.mem_base + (free_mem_first_chunk * chunk_size);
                    var aligned_alloc_slice = @intToPtr([*]T, try utils.ceilRoundToMultiple(alloc_addr, @alignOf(T)));
                    return aligned_alloc_slice[0 .. n - 1];
                }
                return Error.OutOfMem;
            }

            var first_chunk = self.used_chunks;
            var last_chunk = self.used_chunks + req_chunks;
            self.used_chunks += req_chunks;

            for (self.kernel_mem[first_chunk..last_chunk]) |*chunk| {
                chunk.* = true;
            }
            var alloc_addr = self.mem_base + (first_chunk * chunk_size);
            var aligned_alloc_slice = @intToPtr([*]T, try utils.ceilRoundToMultiple(alloc_addr, @alignOf(T)));
            return aligned_alloc_slice[0 .. n - 1];
        }

        /// finds continous free memory in fragmented kernel memory; marks returned memory as not free!
        pub fn findFree(self: *Self, to_chunk: usize, req_size: usize) !?usize {
            var continous_chunks: usize = 0;
            var req_chunks = (try std.math.divCeil(usize, req_size, chunk_size)) - 1;
            for (self.kernel_mem) |chunk, i| {
                if (i >= to_chunk) {
                    return null;
                }

                if (chunk) {
                    continous_chunks += 1;
                } else {
                    continous_chunks = 0;
                }
                if (continous_chunks >= req_chunks) {
                    var first_chunk = i - req_chunks;
                    return first_chunk;
                }
            }
            return null;
        }

        pub fn free(self: *Self, to_free: anytype) !void {
            const Slice = @typeInfo(@TypeOf(to_free)).Pointer;
            const byte_slice = std.mem.sliceAsBytes(to_free);
            const size = byte_slice.len + if (Slice.sentinel != null) @sizeOf(Slice.child) else 0;
            if (size == 0) return;

            // compensating for alignment
            const addr_unaligned = byte_slice.ptr - ((try utils.ceilRoundToMultiple(chunk_size, @alignOf(@TypeOf(to_free)))) - chunk_size);

            if (@ptrToInt(addr_unaligned) > (self.mem_base + (max_chunks * chunk_size)))
                return Error.AddrNotInMem;

            var n_chunk_to_free: usize = std.math.sub(usize, @ptrToInt(addr_unaligned), self.mem_base) catch {
                return Error.AddrNotInMem;
            };

            var first_chunk_to_free: usize = n_chunk_to_free - (try std.math.divFloor(usize, size, chunk_size));

            for (self.kernel_mem[first_chunk_to_free .. first_chunk_to_free + n_chunk_to_free]) |*chunk| {
                chunk.* = false;
            }
        }
    };
}
