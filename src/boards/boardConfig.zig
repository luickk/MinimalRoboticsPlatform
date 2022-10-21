const std = @import("std");

pub const AddrSpace = enum(u8) {
    ttbr1 = 1,
    ttbr0 = 0,

    pub fn isKernelSpace(self: AddrSpace) bool {
        return @enumToInt(self) != 0;
    }
};

pub const Granule = struct {
    pub const GranuleParams = struct {
        page_size: usize,
        // not really neccessary but required to keep section size down
        table_size: usize,
        lvls_required: TransLvl,
    };
    // correct term for .page_size is .block_size
    pub const FourkSection: GranuleParams = .{ .page_size = 2097152, .table_size = 512, .lvls_required = .second_lvl };
    pub const Fourk: GranuleParams = .{ .page_size = 4096, .table_size = 512, .lvls_required = .third_lvl };
    pub const Sixteenk: GranuleParams = .{ .page_size = 16384, .table_size = 2048, .lvls_required = .third_lvl };
    pub const Sixtyfourk: GranuleParams = .{ .page_size = 65536, .table_size = 8192, .lvls_required = .second_lvl };
};

pub fn calctotalTablesReq(granule: Granule.GranuleParams, mem_size: usize) !usize {
    const req_descriptors = try std.math.divExact(usize, mem_size, granule.page_size);

    var req_table_total: usize = 0;
    var ci_lvl: usize = 1;
    while (ci_lvl <= @enumToInt(granule.lvls_required) + 1) : (ci_lvl += 1) {
        req_table_total += try std.math.divCeil(usize, req_descriptors, std.math.pow(usize, granule.table_size, ci_lvl));
    }
    return req_table_total;
}

pub fn calcPageTableSizeTotal(gran: Granule.GranuleParams, mem_size: usize) !usize {
    return (try calctotalTablesReq(gran, mem_size)) * gran.table_size;
}

pub const TransLvl = enum(usize) { first_lvl = 0, second_lvl = 1, third_lvl = 2 };

pub const BoardConfig = struct {
    pub const SupportedBoards = enum {
        raspi3b,
        qemuVirt,
    };

    pub const BoardMemLayout = struct {
        pub const RamMemLayout = struct {
            kernel_space_size: usize,
            kernel_space_phys: usize,
            kernel_space_gran: Granule.GranuleParams,

            user_space_size: usize,
            user_space_phys: usize,
            user_space_gran: Granule.GranuleParams,
        };

        va_start: usize,

        bl_stack_size: usize,
        k_stack_size: usize,

        has_rom: bool,
        rom_start_addr: ?usize,
        rom_size: ?usize,
        bl_load_addr: ?usize,

        ram_start_addr: usize,
        ram_size: usize,
        ram_layout: RamMemLayout,

        storage_start_addr: usize,
        storage_size: usize,
    };

    board: SupportedBoards,
    mem: BoardMemLayout,
    qemu_launch_command: []const []const u8,

    pub fn checkConfig(self: BoardConfig) void {
        if (!self.mem.has_rom and self.mem.rom_start_addr == null and self.mem.bl_load_addr == null)
            @panic("if there is no rom, a boot loader start (or entry) address is required! \n");
        if (!self.mem.has_rom and self.mem.rom_start_addr != null and self.mem.bl_load_addr != null)
            @panic("if there is rom, no boot loader start (or entry) address is supported at the moment! \n");
        if (self.mem.ram_layout.kernel_space_size + self.mem.ram_layout.user_space_size > self.mem.ram_size)
            @panic("since no swapping is supported, user/kernel space cannot exceed ram size \n");
        // optional does does not support equal operator..
        if ((!self.mem.has_rom and self.mem.rom_size == null and self.mem.rom_start_addr != null) or (self.mem.rom_size != null and self.mem.rom_start_addr == null))
            @panic("if rom is disabled, both rom addr and len have to be null \n");
    }
};
