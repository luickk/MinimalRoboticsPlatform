const std = @import("std");
const kprint = @import("serial.zig").kprint;
const utils = @import("utils.zig");
const addr = @import("raspberryAddr.zig");

// (this is my first ever allocator; I've not read any other code base; this implementation is probably slow and ineffective!.)
// todo => alignment!!!
pub fn KernelAllocator(comptime mem_size: usize, comptime chunk_size: usize) type {
    const n_chunks = try std.math.divTrunc(usize, mem_size, chunk_size);

    return struct {
        const Self = @This();
        const Error = error{
            OutOfMem,
            AddrNotInMem,
            AddrNotValid,
        };

        const Chunk = struct {
            // bitmask
            free: bool,
        };

        kernel_mem: *[mem_size]u8,
        kernel_mem_used: usize,

        chunks: [n_chunks]Chunk,
        used_chunks: usize,

        pub fn init(mem_start: usize) !Self {
            var ka = Self{
                .kernel_mem = @intToPtr(*[mem_size]u8, mem_start),
                .kernel_mem_used = 0,

                .chunks = [_]Chunk{.{ .free = true }} ** n_chunks,
                .used_chunks = 0,
            };
            return ka;
        }

        pub fn alloc(self: *Self, comptime T: type, n: usize) ![]T {
            var size = @sizeOf(T) * n;
            var req_chunks = try std.math.divCeil(usize, size, chunk_size);
            if (try self.findFree(self.used_chunks, size)) |free_mem| {
                return @as([]T, free_mem);
            }
            if (self.used_chunks + req_chunks > n_chunks)
                return Error.OutOfMem;

            var first_chunk = self.used_chunks;
            var last_chunk = self.used_chunks + req_chunks;
            self.used_chunks += req_chunks;
            self.kernel_mem_used += req_chunks * chunk_size;

            var i: usize = 0;
            while (i < req_chunks) : (i += 1) {
                self.chunks[first_chunk + i].free = false;
            }
            return @as([]T, self.kernel_mem[first_chunk * chunk_size .. last_chunk * chunk_size]);
        }

        pub fn free(self: *Self, comptime T: type, to_free: []T) !void {
            if (@ptrToInt(to_free.ptr) > (@ptrToInt(&self.kernel_mem[0]) + mem_size))
                return Error.AddrNotInMem;

            var offset: usize = std.math.sub(usize, @ptrToInt(to_free.ptr), @ptrToInt(&self.kernel_mem[0])) catch {
                return Error.AddrNotInMem;
            };

            var req_chunks = try std.math.divCeil(usize, to_free.len, chunk_size);

            // indexed chunk must be freed as well
            var first_chunk_index = try std.math.divFloor(usize, offset, chunk_size);

            var i: usize = 0;
            while (i < req_chunks) : (i += 1) {
                self.chunks[first_chunk_index + i].free = true;
            }
        }

        /// finds continous free memory in fragmented kernel memory; marks returned memory as not free!
        pub fn findFree(self: *Self, to_chunk: usize, min_size: usize) !?[]u8 {
            var continous_chunks: usize = 0;
            var req_chunks = try std.math.divCeil(usize, min_size, chunk_size);
            for (self.chunks) |*chunk, i| {
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

                    var j: usize = 0;
                    while (j < req_chunks) : (j += 1) {
                        self.chunks[first_chunk + j].free = false;
                    }
                    kprint("free used at chunk: {d} \n", .{first_chunk});
                    var kernel_mem_offset = first_chunk * chunk_size;
                    return self.kernel_mem[kernel_mem_offset .. kernel_mem_offset + min_size];
                }
            }
            return null;
        }
    };
}
