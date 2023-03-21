const std = @import("std");
const arm = @import("arm");
const board = @import("board");
const utils = @import("utils");
const kprint = @import("periph").uart.UartWriter(.ttbr1).kprint;
const mmu = arm.mmu;

const granule = board.config.mem.va_user_space_gran;
const userSpaceSizeInBytes = board.config.mem.user_space_size;
const maxChunks: usize = @divExact(userSpaceSizeInBytes, granule.page_size);

pub const UserPageAllocator = struct {
    const Error = error{
        OutOfChunks,
        OutOfMem,
        PageAllocMinimum,
        PageAddrDoesNotAlign,
        AddrNotInMem,
        AddrNotValid,
    };

    kernel_mem: std.bit_set.ArrayBitSet(usize, maxChunks),
    mem_start: usize,
    curr_page_pointer: usize,

    pub fn init() !UserPageAllocator {
        return UserPageAllocator{
            .kernel_mem = std.bit_set.ArrayBitSet(usize, maxChunks).initEmpty(),
            // virt userspace 0x0
            .mem_start = 0,
            .curr_page_pointer = 0,
        };
    }

    pub fn allocNPage(self: *UserPageAllocator, n: usize) ![]u8 {
        if (n <= 0) return Error.PageAllocMinimum;
        if (self.curr_page_pointer + n > self.kernel_mem.capacity()) {
            return try self.searchFreePages(n);
        }
        var ret_slice: []u8 = undefined;
        ret_slice.ptr = @alignCast(granule.page_size, @intToPtr([*]u8, self.mem_start + self.curr_page_pointer * granule.page_size));
        ret_slice.len = granule.page_size * n;
        self.curr_page_pointer += n;
        // kprint("allocation addr: {*} \n", .{ret_slice.ptr});
        return ret_slice;
    }

    fn searchFreePages(self: *UserPageAllocator, req_pages: usize) ![]u8 {
        var iterator = self.kernel_mem.iterator(.{ .kind = .set });
        var i: usize = 0;
        var curr_set_bit_index: usize = 0;
        var last_set_bit_index: usize = 0;
        while (i <= self.kernel_mem.capacity()) : (i += 1) {
            curr_set_bit_index = iterator.next() orelse return Error.OutOfMem;
            if (curr_set_bit_index - last_set_bit_index >= req_pages) {
                var ret_slice: []u8 = undefined;
                ret_slice.ptr = @alignCast(granule.page_size, @intToPtr([*]u8, last_set_bit_index * granule.page_size));
                ret_slice.len = granule.page_size * req_pages;
                return ret_slice;
            }
            last_set_bit_index = curr_set_bit_index;
        }
        return Error.OutOfMem;
    }

    pub fn freeNPage(self: *UserPageAllocator, page_addr: []u8, n: usize) !void {
        if ((try std.math.mod(usize, utils.toTtbr0(usize, @ptrToInt(page_addr.ptr)), granule.page_size)) != 0)
            return Error.PageAddrDoesNotAlign;

        var pointing_addr_start: usize = std.math.sub(usize, utils.toTtbr0(usize, @ptrToInt(page_addr.ptr)), self.mem_start) catch {
            return Error.AddrNotInMem;
        };
        // safe bc page_address is multiple of page_size
        var n_page = pointing_addr_start / granule.page_size;
        self.kernel_mem.setRangeValue(.{ .start = n_page, .end = n_page + n + n }, false);
        self.curr_page_pointer -= n;
    }
};
