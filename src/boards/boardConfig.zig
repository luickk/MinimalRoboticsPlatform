const std = @import("std");

pub const supportedBoards = enum {
    raspi3b,
    qemuVirt,
};

pub fn calctotalTablesReq(granule: GranuleParams, mem_size: usize) !usize {
    const req_pages = try std.math.divExact(usize, mem_size, granule.page_size);

    var req_table_total: usize = 0;
    var ci_lvl: usize = 1;
    while (ci_lvl <= @enumToInt(granule.lvls_required) + 1) : (ci_lvl += 1) {
        req_table_total += try std.math.divCeil(usize, req_pages, std.math.pow(usize, granule.table_size, ci_lvl));
    }
    return req_table_total;
}

pub fn calcPageTableSizeTotal(gran: GranuleParams, mem_size: usize) !usize {
    return (try calctotalTablesReq(gran, mem_size)) * gran.table_size;
}

pub const Granule = struct {
    pub const Fourk: GranuleParams = .{ .page_size = 4096, .table_size = 512, .lvls_required = .third_lvl };
    pub const Sixteenk: GranuleParams = .{ .page_size = 16384, .table_size = 2048, .lvls_required = .third_lvl };
    pub const Sixtyfourk: GranuleParams = .{ .page_size = 65536, .table_size = 8192, .lvls_required = .second_lvl };
    pub const Section: GranuleParams = .{ .page_size = 2097152, .table_size = 512, .lvls_required = .first_lvl };
};

pub const TransLvl = enum(usize) { first_lvl = 0, second_lvl = 1, third_lvl = 2 };

pub const GranuleParams = struct {
    page_size: usize,
    // not really neccessary but required to keep section size down
    table_size: usize,
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

    // todo => remove those...
    pub fn calcPageTableSizeKernel(self: RamMemLayout) !usize {
        return (try calctotalTablesReq(self.kernel_space_gran, self.kernel_space_size)) * (self.kernel_space_gran.page_size / 8);
    }

    pub fn calcPageTableSizeUser(self: RamMemLayout) !usize {
        return (try calctotalTablesReq(self.user_space_gran, self.user_space_size)) * (self.user_space_gran.page_size / 8);
    }
};

pub const BoardMemLayout = struct {
    va_start: usize,

    bl_stack_size: usize,
    k_stack_size: usize,

    rom_start_addr: ?usize,
    rom_size: ?usize,

    ram_start_addr: usize,
    ram_size: usize,
    ram_layout: RamMemLayout,

    bl_load_addr: ?usize,

    storage_start_addr: usize,
    storage_size: usize,
};

pub const BoardConfig = struct {
    board: supportedBoards,
    mem: BoardMemLayout,
    qemu_launch_command: []const []const u8,

    pub fn checkConfig(cfg: BoardConfig) void {
        if (cfg.mem.rom_start_addr == null and cfg.mem.bl_load_addr == null)
            @panic("if there is no rom, a boot loader start (or entry) address is required! \n");
        if (cfg.mem.rom_start_addr != null and cfg.mem.bl_load_addr != null)
            @panic("if there is rom, no boot loader start (or entry) address is supported at the moment! \n");
        if (cfg.mem.ram_layout.kernel_space_size + cfg.mem.ram_layout.user_space_size > cfg.mem.ram_size)
            @panic("since no swapping is supported, user/kernel space cannot exceed ram size \n");
        // optional does does not support equal operator..
        if ((cfg.mem.rom_size == null and cfg.mem.rom_start_addr != null) or (cfg.mem.rom_size != null and cfg.mem.rom_start_addr == null))
            @panic("if rom is disabled, both rom addr and len have to be null \n");
    }
};
