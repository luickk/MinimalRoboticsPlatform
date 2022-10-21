const std = @import("std");
const arm = @import("arm");
const board = @import("board");
const utils = @import("utils");
const kprint = @import("periph").uart.UartWriter(.ttbr1).kprint;

const mmu = arm.mmu;

pub fn UserPageAllocator(comptime mem_size: usize, comptime granule: board.boardConfig.GranuleParams) !type {
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

        kernel_mem: [n_pages]bool,
        mem_start: usize,
        curr_page_pointer: usize,
        granule: board.boardConfig.GranuleParams,

        pub fn init(mem_start: usize) !Self {
            if ((try std.math.mod(usize, mem_start, granule.page_size)) != 0)
                return Error.PageAddrDoesNotAlign;

            return Self{
                .kernel_mem = [_]bool{false} ** n_pages,
                .mem_start = mem_start,
                .curr_page_pointer = 0,
                .granule = gran,
            };
        }

        pub fn allocNPage(self: *Self, n: usize) !*anyopaque {
            var ret_addr: *anyopaque = undefined;
            if (self.curr_page_pointer + n > self.kernel_mem.len) {
                return try self.searchFreePages(n);
            }
            for (self.kernel_mem[self.curr_page_pointer .. self.curr_page_pointer + n]) |*page| {
                page.* = true;
            }
            ret_addr = @ptrCast(*anyopaque, &self.kernel_mem[self.curr_page_pointer]);
            self.curr_page_pointer += n;
            return @intToPtr(*anyopaque, self.mem_start + @ptrToInt(ret_addr) * self.granule.page_size);
        }

        fn searchFreePages(self: *Self, req_pages: usize) !*anyopaque {
            var free_pages_in_row: usize = 0;
            for (self.kernel_mem) |*page, i| {
                if (!page.*) {
                    free_pages_in_row += 1;
                } else {
                    free_pages_in_row = 0;
                }
                if (free_pages_in_row >= req_pages) {
                    return @ptrCast(*anyopaque, &self.kernel_mem[i - req_pages]);
                }
            }
            return Error.OutOfMem;
        }

        pub fn freeNPage(self: *Self, page_addr: *anyopaque, n: usize) !void {
            if ((try std.math.mod(usize, mmu.toUnsecure(usize, @ptrToInt(page_addr)), granule.page_size)) != 0)
                return Error.PageAddrDoesNotAlign;

            var pointing_addr_start: usize = std.math.sub(usize, mmu.toUnsecure(usize, @ptrToInt(page_addr)), self.mem_start) catch {
                return Error.AddrNotInMem;
            };
            // safe bc page_address is multiple of page_size
            var n_page = pointing_addr_start / self.granule.page_size;
            for (self.kernel_mem[n_page .. n_page + n]) |*page| {
                page.* = false;
            }
            self.curr_page_pointer -= n;
        }
    };
}
