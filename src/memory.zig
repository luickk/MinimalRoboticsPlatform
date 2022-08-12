const std = @import("std");
const kprint = @import("serial.zig").kprint;
const utils = @import("utils.zig");
const addr = @import("raspberryAddr.zig");

// (this is my first ever allocator; I've not read any other code base; this implementation is probably slow and ineffective!.)
// todo => alignment!!!
pub fn KernelAllocator(comptime mem_size: usize, comptime page_size: usize, comptime chunk_size: usize) type {
    const n_pages = try std.math.divTrunc(usize, mem_size, page_size);
    const n_chunks_per_page = try std.math.divTrunc(usize, page_size, chunk_size);
    const max_allocs: usize = 10000;
    return struct {
        const Self = @This();
        const Error = error{
            OutOfPages,
            OutOfMem,
            OutOfAllocs,
            AddrNotInMem,
            AddrNotValid,
            RequiresCrossPageChunking, // todo => implement!
        };

        const Chunk = struct {
            // bitmask
            free: bool,
        };
        const Page = struct {
            chunks: [n_chunks_per_page]Chunk,
            free: bool,
            used_chunks: usize,
        };

        const Allocation = struct {
            in_page: usize,
            chunk_range: struct { first_chunk: usize, last_chunk: usize },
        };

        kernel_mem: *[mem_size]u8,
        kernel_mem_used: usize,

        pages: [n_pages]Page,
        used_pages: usize,

        allocations: [max_allocs]Allocation,
        used_allocs: usize,

        pub fn init(mem_start: usize) !Self {
            var ka = Self{
                .kernel_mem = @intToPtr(*[mem_size]u8, mem_start),
                .kernel_mem_used = 0,

                // unfolding whole mem tree right at the beginning
                .pages = [_]Page{.{ .chunks = [_]Chunk{.{ .free = true }} ** n_chunks_per_page, .free = true, .used_chunks = 0 }} ** n_pages,
                .used_pages = 0,

                .allocations = [_]Allocation{.{ .in_page = 0, .chunk_range = .{ .first_chunk = undefined, .last_chunk = undefined } }} ** max_allocs,
                .used_allocs = 0,
            };
            try ka.newPage();
            return ka;
        }

        fn newPage(self: *Self) !void {
            if (self.used_pages >= self.pages.len)
                // todo => search for free space
                return Error.OutOfPages;
            self.pages[self.used_pages].free = false;
            self.used_pages += 1;
            self.kernel_mem_used += page_size;
        }

        pub fn alloc(self: *Self, comptime T: type, n: usize) ![]T {
            var current_page = self.used_pages - 1;
            var req_chunks = try std.math.divCeil(usize, @sizeOf(T) * n, chunk_size);
            if (req_chunks > n_chunks_per_page)
                return Error.RequiresCrossPageChunking;

            if ((self.pages[current_page].used_chunks + req_chunks) > n_chunks_per_page) {
                try self.newPage();
                current_page = self.used_pages - 1;
            }

            if (self.used_allocs >= max_allocs)
                return Error.OutOfAllocs;
            self.allocations[self.used_allocs].in_page = current_page;
            self.allocations[self.used_allocs].chunk_range = .{ .first_chunk = self.pages[current_page].used_chunks, .last_chunk = self.pages[current_page].used_chunks + req_chunks };
            var relative_mem_slice = self.kernel_mem[(current_page * page_size) + (self.allocations[self.used_allocs].chunk_range.first_chunk * chunk_size) .. (current_page * page_size) + (self.allocations[self.used_allocs].chunk_range.last_chunk * chunk_size)];
            self.pages[current_page].used_chunks += req_chunks;
            self.used_allocs += 1;
            return @as([]T, relative_mem_slice);
        }

        pub fn free(self: *Self, comptime T: type, to_free: []T) !void {
            if (@ptrToInt(to_free.ptr) > (@ptrToInt(&self.kernel_mem[0]) + mem_size))
                return Error.AddrNotInMem;

            var offset: usize = std.math.sub(usize, @ptrToInt(to_free.ptr), @ptrToInt(&self.kernel_mem[0])) catch {
                return Error.AddrNotInMem;
            };

            var req_chunks = try std.math.divCeil(usize, to_free.len, chunk_size);

            var in_page = try std.math.divTrunc(usize, offset, page_size);
            var offset_relative_to_page: usize = offset - (in_page * page_size);
            if (offset_relative_to_page > page_size)
                return Error.AddrNotValid;
            // indexed chunk must be freed as well
            var first_chunk_index = try std.math.divFloor(usize, offset_relative_to_page, chunk_size);

            var i: usize = 0;
            while (i <= req_chunks) : (i += 1) {
                self.pages[in_page].chunks[first_chunk_index + i].free = true;
            }
            self.pages[in_page].used_chunks -= req_chunks;
        }
    };
}
