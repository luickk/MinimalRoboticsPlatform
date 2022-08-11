const std = @import("std");
const kprint = @import("serial.zig").kprint;
const utils = @import("utils.zig");
const addr = @import("raspberryAddr.zig");

// todo => use anon struct for named inp params
pub fn KernelAllocator(comptime mem_size: usize, comptime buff_pages_size: usize, comptime buff_allocs_size: usize, comptime page_size: usize) type {
    return struct {
        const Self = @This();
        const Error = error{
            OutOfPages,
            OutOfMem,
        };

        const Page = struct {
            data: []u8,
            used: usize,
        };

        const Allocation = struct {
            data: []u8,
            in_page: usize,
        };
        kernel_mem: [mem_size]u8,
        kernel_mem_used: usize,

        pages: [buff_pages_size]Page,
        n_pages: usize,

        allocations: [buff_allocs_size]Allocation,
        n_allocations: usize,

        pub fn init(mem_start: usize) !Self {
            var ka = Self{
                .kernel_mem = @intToPtr([*]u8, mem_start)[0..mem_size].*,
                .kernel_mem_used = 0,
                .n_pages = 0,
                .pages = undefined,
                .allocations = undefined,
                .n_allocations = 0,
            };
            try ka.newPage();
            return ka;
        }

        fn newPage(self: *Self) !void {
            if (self.n_pages >= self.pages.len)
                return Error.OutOfPages;
            self.pages[self.n_pages] = Page{ .data = self.kernel_mem[self.kernel_mem_used .. self.kernel_mem_used + page_size], .used = 0 };
            self.n_pages += 1;
            self.kernel_mem_used += page_size;
            kprint("new page \n", .{});
        }

        pub fn allocU8(self: *Self, size: usize) ![]u8 {
            var current_page = self.n_pages - 1;

            // zig does not let me do that ):
            // todo => fix (temp solution: increase page size)
            // if ((self.pages[current_page].used + size) > self.pages[current_page].data.len) {
            //     try self.newPage();
            //     kprint("full new page \n", .{});
            // }

            self.allocations[self.n_allocations] = Allocation{ .data = self.pages[current_page].data[self.pages[current_page].used .. self.pages[current_page].used + size], .in_page = current_page };
            self.n_allocations += 1;

            self.pages[current_page].used += size;

            kprint("allocated \n", .{});
            return self.allocations[self.n_allocations].data;
        }

        pub fn free(self: *Self, free_addr: []u8) void {
            var offset = @ptrToInt(free_addr.ptr) - @ptrToInt(&self.kernel_mem[0]);
            kprint("offset: {d} \n", .{offset});
        }
    };
}
