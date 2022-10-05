const std = @import("std");
const periph = @import("peripherals");
const utils = @import("utils");

const kprint = periph.serial.kprint;
const addr = periph.rbAddr;

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

        pub fn init(mem_base: usize) !Self {
            var ka = Self{
                .kernel_mem = [_]usize{false} ** max_chunks,
                .chunks_used = 0,
                .mem_base = mem_base,
            };
            return ka;
        }

        pub fn alloc(self: *Self, comptime T: type, n: usize) !*T {
            var size = @sizeOf(T) * n;
            var req_chunks = try std.math.divCeil(usize, size, chunk_size);
            if (try self.findFree(self.used_chunks, size)) |free_mem| {
                return @as([]T, free_mem);
            }
            if (self.used_chunks + req_chunks > max_chunks)
                return Error.OutOfMem;

            var first_chunk = self.used_chunks;
            var last_chunk = self.used_chunks + req_chunks;
            self.used_chunks += req_chunks;

            for (self.kernel_mem[first_chunk..last_chunk]) |*chunk| {
                chunk.* = true;
            }
            return @intToPtr(*T, self.mem_base + (first_chunk * chunk_size));
        }

        pub fn free(self: *Self, comptime T: type, to_free: T) !void {
            if (@ptrToInt(to_free.ptr) > (self.mem_base + (max_chunks * chunk_size)))
                return Error.AddrNotInMem;

            var n_chunk_to_free: usize = std.math.sub(usize, @ptrToInt(to_free.ptr), @ptrToInt(self.mem_base)) catch {
                return Error.AddrNotInMem;
            };

            var first_chunk_to_free: usize = n_chunk_to_free - (try std.math.divFloor(usize, to_free.len, chunk_size));

            for (self.kernel_mem[first_chunk_to_free .. first_chunk_to_free + n_chunk_to_free]) |*chunk| {
                chunk.* = false;
            }
        }

        /// finds continous free memory in fragmented kernel memory; marks returned memory as not free!
        pub fn findFree(self: *Self, to_chunk: usize, req_size: usize) !?struct { first_chunk: usize, last_chunk: usize } {
            var continous_chunks: usize = 0;
            var req_chunks = try std.math.divCeil(usize, req_size, chunk_size);
            for (self.kernel_mem) |*chunk, i| {
                if (i >= to_chunk) {
                    return null;
                }

                if (chunk.free) {
                    continous_chunks += 1;
                } else {
                    continous_chunks = 0;
                }
                if (continous_chunks >= req_chunks) {
                    var first_chunk: usize = (i + 1) - req_chunks;
                    return .{ first_chunk, first_chunk + req_chunks };
                }
            }
            return null;
        }
    };
}
