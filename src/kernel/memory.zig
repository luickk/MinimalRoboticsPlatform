const std = @import("std");
const periph = @import("peripherals");
const board = @import("board");
const utils = @import("utils");

const kprint = periph.serial.kprint;

pub fn UserSpaceAllocator(comptime mem_size: usize, comptime granule: board.layout.GranuleParams) !type {
    const n_pages = try std.math.divExact(usize, mem_size, granule.page_size);
    const gran = granule;
    return struct {
        const Self = @This();
        const Error = error{
            OutOfMem,
            PageAddrDoesNotAlign,
            AddrNotInMem,
            AddrNotValid,
        };

        kernel_mem: *[n_pages]bool,
        curr_page_pointer: usize,
        granule: board.layout.GranuleParams,

        pub fn init(mem_start: usize) Self {
            return Self{
                .kernel_mem = @intToPtr(*[n_pages]bool, mem_start),
                .curr_page_pointer = 0,
                .granule = gran,
            };
        }

        pub fn allocNPage(self: *Self, n: usize) !*anyopaque {
            var ret_addr: *anyopaque = undefined;
            if (self.curr_page_pointer + n > self.kernel_mem.len)
                return try self.searchFreePages(n);
            for (self.kernel_mem[self.curr_page_pointer .. self.curr_page_pointer + n]) |*page| {
                page.* = true;
            }
            ret_addr = @ptrCast(*anyopaque, &self.kernel_mem[self.curr_page_pointer]);
            self.curr_page_pointer += n;
            return @intToPtr(*anyopaque, @ptrToInt(ret_addr) * self.granule.page_size);
        }

        fn searchFreePages(self: *Self, req_pages: usize) !*anyopaque {
            var free_pages_in_row: usize = 0;
            for (self.kernel_mem) |*page, i| {
                if (page.*)
                    free_pages_in_row += 1;
                if (free_pages_in_row >= req_pages)
                    return @ptrCast(*anyopaque, &self.kernel_mem[i - req_pages]);
            }
            return Error.OutOfMem;
        }

        pub fn freeNPage(self: *Self, page_addr: *anyopaque, n: usize) !void {
            if ((try std.math.mod(usize, @ptrToInt(page_addr), granule.page_size)) != 0)
                return Error.PageAddrDoesNotAlign;
            var offset: usize = std.math.sub(usize, @ptrToInt(page_addr), @ptrToInt(&self.kernel_mem[0])) catch {
                return Error.AddrNotInMem;
            };
            for (self.kernel_mem[offset .. offset + n]) |*page| {
                page.* = false;
            }
            self.curr_page_pointer -= n;
        }
    };
}
