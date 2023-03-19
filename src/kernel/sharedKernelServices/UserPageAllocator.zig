const std = @import("std");
const arm = @import("arm");
const board = @import("board");
const utils = @import("utils");
const kprint = @import("periph").uart.UartWriter(.ttbr1).kprint;

const mmu = arm.mmu;

const GranuleParams = board.boardConfig.Granule.GranuleParams;

// todo => fix. rebuild userpageallocator.....
const maxChunks: usize = 150000;

pub const UserPageAllocator = struct {
    // virt userspace 0x0
    const mem_start: usize = 0;

    const Error = error{
        OutOfChunks,
        OutOfMem,
        PageAddrDoesNotAlign,
        AddrNotInMem,
        AddrNotValid,
    };

    kernel_mem: std.bit_set.ArrayBitSet(usize, maxChunks),
    mem_start: usize,
    curr_page_pointer: usize,
    granule: GranuleParams,

    pub fn init(comptime mem_size: usize, comptime granule: GranuleParams) !UserPageAllocator {
        if (try std.math.divCeil(usize, mem_size, granule.page_size) > maxChunks) return Error.OutOfChunks;
        return UserPageAllocator{
            .kernel_mem = std.bit_set.ArrayBitSet(usize, maxChunks).initFull(),
            .mem_start = mem_start,
            .curr_page_pointer = 0,
            .granule = granule,
        };
    }

    pub fn allocNPage(self: *UserPageAllocator, n: usize) ![]u8 {
        if (self.curr_page_pointer + n > self.kernel_mem.count()) {
            return try self.searchFreePages(n);
        }
        self.kernel_mem.setRangeValue(.{ .start = self.curr_page_pointer, .end = self.curr_page_pointer + n }, true);

        self.curr_page_pointer += n;
        var ret_slice: []u8 = undefined;
        ret_slice.ptr = @alignCast(4096, @intToPtr([*]u8, self.mem_start + self.curr_page_pointer * self.granule.page_size));
        ret_slice.len = self.granule.page_size * n;
        // kprint("allocation addr: {*} \n", .{ret_slice.ptr});
        return ret_slice;
    }

    fn searchFreePages(self: *UserPageAllocator, req_pages: usize) ![]u8 {
        var iterator = self.kernel_mem.iterator(.{});
        var i: usize = 0;
        var curr_set_bit_index: usize = 0;
        var last_set_bit_index: usize = 0;
        while (i <= self.kernel_mem.capacity()) : (i += 1) {
            curr_set_bit_index = iterator.next() orelse return Error.OutOfMem;
            if (curr_set_bit_index - last_set_bit_index >= req_pages) {
                var ret_slice: []u8 = undefined;
                ret_slice.ptr = @alignCast(4096, @intToPtr([*]u8, last_set_bit_index * self.granule.page_size));
                ret_slice.len = self.granule.page_size * req_pages;
                return ret_slice;
            }
            last_set_bit_index = curr_set_bit_index;
        }
        return Error.OutOfMem;
    }

    pub fn freeNPage(self: *UserPageAllocator, page_addr: *anyopaque, n: usize) !void {
        if ((try std.math.mod(usize, utils.toTtbr0(usize, @ptrToInt(page_addr)), self.granule.page_size)) != 0)
            return Error.PageAddrDoesNotAlign;

        var pointing_addr_start: usize = std.math.sub(usize, utils.toTtbr0(usize, @ptrToInt(page_addr)), self.mem_start) catch {
            return Error.AddrNotInMem;
        };
        // safe bc page_address is multiple of page_size
        var n_page = pointing_addr_start / self.granule.page_size;
        self.kernel_mem.setRangeValue(.{ .start = n_page, .end = n_page + n + n }, false);
        self.curr_page_pointer -= n;
    }
};
