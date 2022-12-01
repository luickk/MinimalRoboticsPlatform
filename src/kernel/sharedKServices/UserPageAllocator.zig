const std = @import("std");
const arm = @import("arm");
const board = @import("board");
const utils = @import("utils");
const kprint = @import("periph").uart.UartWriter(.ttbr1).kprint;

const mmu = arm.mmu;

const GranuleParams = board.boardConfig.Granule.GranuleParams;

// todo => put mem_start back as init() args
pub fn UserPageAllocator(comptime mem_size: usize, comptime granule: GranuleParams) !type {
    const n_pages = try std.math.divExact(usize, mem_size, granule.page_size);
    const gran = granule;
    // virt userspace 0x0
    const mem_start: usize = 0;
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
        granule: GranuleParams,

        pub fn init() !Self {
            return Self{
                .kernel_mem = [_]bool{false} ** n_pages,
                .mem_start = mem_start,
                .curr_page_pointer = 0,
                .granule = gran,
            };
        }

        pub fn allocNPage(self: *Self, n: usize) !*align(4096) anyopaque {
            if (self.curr_page_pointer + n > self.kernel_mem.len) {
                return try self.searchFreePages(n);
            }
            for (self.kernel_mem[self.curr_page_pointer .. self.curr_page_pointer + n]) |*page| {
                page.* = true;
            }
            self.curr_page_pointer += n;
            return @alignCast(4096, @intToPtr(*anyopaque, self.mem_start + self.curr_page_pointer * self.granule.page_size));
        }

        fn searchFreePages(self: *Self, req_pages: usize) !*align(4096) anyopaque {
            var free_pages_in_row: usize = 0;
            for (self.kernel_mem) |*page, i| {
                if (!page.*) {
                    free_pages_in_row += 1;
                } else {
                    free_pages_in_row = 0;
                }
                if (free_pages_in_row >= req_pages) {
                    return @alignCast(4096, @intToPtr(*anyopaque, (i - req_pages) * self.granule.page_size));
                }
            }
            return Error.OutOfMem;
        }

        pub fn freeNPage(self: *Self, page_addr: *anyopaque, n: usize) !void {
            if ((try std.math.mod(usize, mmu.toTtbr0(usize, @ptrToInt(page_addr)), granule.page_size)) != 0)
                return Error.PageAddrDoesNotAlign;

            var pointing_addr_start: usize = std.math.sub(usize, mmu.toTtbr0(usize, @ptrToInt(page_addr)), self.mem_start) catch {
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
