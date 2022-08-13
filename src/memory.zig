const std = @import("std");
const kprint = @import("serial.zig").kprint;
const utils = @import("utils.zig");
const addr = @import("raspberryAddr.zig");

// (this is my first ever allocator; I've not read any other code base; this implementation is probably slow and ineffective!.)
// todo => alignment!!!
pub fn KernelAllocator(comptime mem_size: usize, comptime page_size: usize, comptime chunk_size: usize) type {
    const n_pages = try std.math.divTrunc(usize, mem_size, page_size);
    const n_chunks_per_page = try std.math.divTrunc(usize, page_size, chunk_size);

    return struct {
        const Self = @This();
        const Error = error{
            OutOfPages,
            OutOfMem,
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
            // freed chunks are not substraced!
            // this value is only relevant as long as the array's index is on the struct
            // if a new page has been created the not used chunks may be allocated by fragmented memory which does not increase the used_chunks counter
            // since it cannot be known if the memory has already been accounted for.
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

        pub fn init(mem_start: usize) !Self {
            var ka = Self{
                .kernel_mem = @intToPtr(*[mem_size]u8, mem_start),
                .kernel_mem_used = 0,

                // unfolding whole mem tree right at the beginning
                .pages = [_]Page{.{ .chunks = [_]Chunk{.{ .free = true }} ** n_chunks_per_page, .free = true, .used_chunks = 0 }} ** n_pages,
                .used_pages = 0,
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
            var size = @sizeOf(T) * n;
            var req_chunks = try std.math.divCeil(usize, size, chunk_size);
            kprint("size: {d}, rc: {d} \n", .{ size, req_chunks });
            if (req_chunks > n_chunks_per_page)
                return Error.RequiresCrossPageChunking;
            if (try self.findFree(current_page, size)) |free_mem| {
                return @as([]T, free_mem);
            }
            if ((self.pages[current_page].used_chunks + req_chunks) > n_chunks_per_page) {
                try self.newPage();
                current_page = self.used_pages - 1;
            }

            var first_chunk = self.pages[current_page].used_chunks;
            var last_chunk = self.pages[current_page].used_chunks + req_chunks;
            var kernel_mem_page_offset = (current_page * page_size);
            var relative_mem_slice = self.kernel_mem[kernel_mem_page_offset + (first_chunk * chunk_size) .. kernel_mem_page_offset + (last_chunk * chunk_size)];

            self.pages[current_page].used_chunks += req_chunks;
            var i: usize = 0;
            while (i < req_chunks) : (i += 1) {
                self.pages[current_page].chunks[first_chunk + i].free = false;
            }
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
            while (i < req_chunks) : (i += 1) {
                self.pages[in_page].chunks[first_chunk_index + i].free = true;
            }
        }

        /// finds continous free memory in fragmented kernel memory; marks returned memory as not free!
        pub fn findFree(self: *Self, to_page: usize, min_size: usize) !?[]u8 {
            var continous_chunks: usize = 0;
            var req_chunks = try std.math.divCeil(usize, min_size, chunk_size);
            for (self.pages) |*page, p_i| {
                if (p_i >= to_page) {
                    return null;
                }
                for (page.chunks) |*chunk, c_i| {
                    if (chunk.free) {
                        continous_chunks += 1;
                    } else {
                        continous_chunks = 0;
                    }
                    if (continous_chunks >= req_chunks) {
                        var first_chunk: usize = (c_i + 1) - req_chunks;
                        var kernel_mem_offset = (page_size * p_i) + (first_chunk * chunk_size);

                        var i: usize = 0;
                        while (i < req_chunks) : (i += 1) {
                            self.pages[p_i].chunks[first_chunk + i].free = false;
                        }
                        return self.kernel_mem[kernel_mem_offset .. kernel_mem_offset + min_size];
                    }
                }
            }
            return null;
        }
    };
}
