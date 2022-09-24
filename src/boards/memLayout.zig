/// due to recrusive imports in build.zig, some code here is duplicate, most of it belogns to mmu.zig though!
const std = @import("std");

pub const supportedBoards = enum {
    raspi3b,
    qemuRaspi3b, // deprecated! // todo => remove
    qemuVirt,
};

pub fn calctotalTablesReq(granule: GranuleParams, mem_size: usize) !usize {
    var table_len = granule.page_size / 8;
    const req_pages = try std.math.divExact(usize, mem_size, granule.page_size);

    var req_table_total: usize = 0;
    var ccurr_lvl: usize = 1;
    while (ccurr_lvl <= @enumToInt(granule.lvls_required) + 1) : (ccurr_lvl += 1) {
        req_table_total += try std.math.divCeil(usize, req_pages, std.math.pow(usize, table_len, ccurr_lvl));
    }
    return req_table_total;
}

pub const Granule = struct {
    pub const Fourk: GranuleParams = .{ .page_size = 4096, .lvls_required = .third_lvl };
    pub const Sixteenk: GranuleParams = .{ .page_size = 16384, .lvls_required = .third_lvl };
    pub const Sixtyfourk: GranuleParams = .{ .page_size = 65536, .lvls_required = .second_lvl };
    pub const Section: GranuleParams = .{ .page_size = 2097152, .lvls_required = .first_lvl };
};

pub const TransLvl = enum(usize) { first_lvl = 0, second_lvl = 1, third_lvl = 2 };

pub const GranuleParams = struct {
    page_size: usize,
    lvls_required: TransLvl,
};

pub const RamMemLayout = struct {
    kernel_space_size: usize,
    kernel_space_vs: usize,
    kernel_space_phys: usize,
    kernel_space_gran: GranuleParams,

    user_space_size: usize,
    user_space_vs: usize,
    user_space_phys: usize,
    user_space_gran: GranuleParams,

    pub fn calcPageTableSizeKernel(self: RamMemLayout) !usize {
        return (try calctotalTablesReq(self.kernel_space_gran, self.kernel_space_size)) * (self.kernel_space_gran.page_size / 8);
    }

    pub fn calcPageTableSizeUser(self: RamMemLayout) !usize {
        return (try calctotalTablesReq(self.user_space_gran, self.user_space_size)) * (self.user_space_gran.page_size / 8);
    }
};

pub const BoardMemLayout = struct {
    rom_start_addr: usize,
    rom_len: usize,

    ram_start_addr: usize,
    ram_len: usize,
    ram_layout: RamMemLayout,

    bl_load_addr: usize,

    storage_start_addr: usize,
    storage_len: usize,

    pub fn calcPageTableSizeRom(self: BoardMemLayout, gran: GranuleParams) !usize {
        return (try calctotalTablesReq(gran, self.rom_len)) * (gran.page_size / 8);
    }

    pub fn calcPageTableSizeRam(self: BoardMemLayout, gran: GranuleParams) !usize {
        return (try calctotalTablesReq(gran, self.ram_len)) * (gran.page_size / 8);
    }
};

pub const BoardParams = struct {
    board: supportedBoards,
    mem: BoardMemLayout,
    qemu_launch_command: []const []const u8,
};
