const std = @import("std");
const board = @import("board");
const kprint = @import("periph").uart.UartWriter(false).kprint;

pub const DirtyWriter = struct {
    pub const Writer = std.io.Writer(*DirtyWriter, error{}, appendWrite);

    pub fn writer(self: *DirtyWriter) Writer {
        return .{ .context = self };
    }

    /// Same as `append` except it returns the number of bytes written, which is always the same
    /// as `m.len`. The purpose of this function existing is to match `std.io.Writer` API.
    fn appendWrite(self: *DirtyWriter, data: []const u8) error{}!usize {
        _ = self;
        for (data) |ch| {
            @intToPtr(*u8, 0x9000000).* = ch;
        }
        return data.len;
    }
};

pub fn dprint(comptime print_string: []const u8, args: anytype) void {
    var tempW: DirtyWriter = undefined;
    std.fmt.format(tempW.writer(), print_string, args) catch |err| {
        @panic(err);
    };
}

const Granule = board.boardConfig.Granule;
const GranuleParams = board.boardConfig.GranuleParams;
const TransLvl = board.boardConfig.TransLvl;

pub const Mapping = struct {
    mem_size: usize,
    virt_start_addr: usize,
    phys_addr: usize,
    granule: GranuleParams,
    // currently only supported for sections
    flags: ?TableDescriptorAttr,
};

// In addition to an output address, a translation table descriptor that refers to a page or region of memory
// includes fields that define properties of the target memory region. These fields can be classified as
// address map control, access control, and region attribute fields.
pub const TableDescriptorAttr = packed struct {
    // block indicates next trans lvl (or physical for sections) and page the last trans lvl (with physical addr)
    pub const DescType = enum(u1) { block = 0, page = 1 };
    // redirects read from mem tables to mairx reg (domain)
    pub const AttrIndex = enum(u3) { mair0 = 0, mair1 = 1, mair2 = 2, mair3 = 3, mair4 = 4, mair5 = 5, mair6 = 6, mair7 = 7 };
    pub const Sharability = enum(u2) { non_sharable = 0, unpredictable = 1, outer_sharable = 2, innner_sharable = 3 };

    // for Non-secure stage 1 of the EL1&0 translation regime
    pub const Stage1AccessPerm = enum(u2) { only_el1_read_write = 0, read_write = 1, only_el1_read_only = 2, read_only = 3 };
    // for Non-secure EL1&0 stage 2 translation regime
    pub const Stage2AccessPerm = enum(u2) { none = 0, read_only = 1, write_only = 2, read_write = 3 };
    // for secure EL2&3 translation regime
    pub const SecureAccessPerm = enum(u2) { read_write = 0, read_only = 3 };

    // https://armv8-ref.codingbelief.com/en/chapter_d4/d43_1_vmsav8-64_translation_table_descriptor_formats.html
    // https://armv8-ref.codingbelief.com/en/chapter_d4/d43_2_armv8_translation_table_level_3_descriptor_formats.html
    // identifies whether the descriptor is valid, and is 1 for a valid descriptor.
    valid: bool = true,
    // identifies the descriptor type, and is encoded as:
    descType: DescType = .block,

    // https://armv8-ref.codingbelief.com/en/chapter_d4/d43_3_memory_attribute_fields_in_the_vmsav8-64_translation_table_formats_descriptors.html
    attrIndex: AttrIndex = .mair0,
    // For memory accesses from Secure state, specifies whether the output address is in the Secure or Non-secure address map
    ns: bool = false,
    // depends on translation level (Stage2AccessPerm, Stage1AccessPerm, SecureAccessPerm)
    accessPerm: Stage1AccessPerm = .read_only,
    sharableAttr: Sharability = .non_sharable,

    // The access flag indicates when a page or section of memory is accessed for the first time since the
    // Access flag in the corresponding translation table descriptor was set to 0.
    accessFlag: bool = true,
    // the not global bit. Determines whether the TLB descriptor applies to all ASID values, or only to the current ASID value
    notGlobal: bool = false,

    // upper attr following
    _padding: u39 = 0,

    // indicating that the translation table descriptor is one of a contiguous set or descriptors, that might be cached in a single TLB descriptor
    contiguous: bool = false,
    // priviledeg execute-never bit. Determines whether the region is executable at EL1
    pxn: bool = false,
    // execute-never bit. Determines whether the region is executable
    uxn: bool = false,

    _padding2: u10 = 0,

    pub fn asInt(self: TableDescriptorAttr) usize {
        return @bitCast(u64, self);
    }
};

pub const MairReg = packed struct {
    attr0: u8 = 0,
    attr1: u8 = 0,
    attr2: u8 = 0,
    attr3: u8 = 0,
    attr4: u8 = 0,
    attr5: u8 = 0,
    attr6: u8 = 0,
    attr7: u8 = 0,

    pub fn asInt(self: MairReg) usize {
        return @bitCast(u64, self);
    }
};
pub const TcrReg = packed struct {
    t0sz: u6 = 0,
    reserved0: bool = false,
    epd0: bool = false,
    irgno0: u2 = 0,
    orgn0: u2 = 0,
    sh0: u2 = 0,
    tg0: u2 = 0,
    t1sz: u6 = 0,
    a1: bool = false,
    epd1: bool = false,
    irgn1: u2 = 0,
    orgn1: u2 = 0,
    sh1: u2 = 0,
    tg1: u2 = 0,
    ips: u3 = 0,
    reserved1: bool = false,
    as: bool = false,
    tbi0: bool = false,
    tbi1: bool = false,
    ha: bool = false,
    hd: bool = false,
    hpd0: bool = false,
    hpd1: bool = false,
    hwu059: bool = false,
    hwu060: bool = false,
    hwu061: bool = false,
    hwu062: bool = false,
    hwu159: bool = false,
    hwu160: bool = false,
    hwu161: bool = false,
    hwu162: bool = false,
    tbid0: bool = false,
    tbid1: bool = false,
    nfd0: bool = false,
    nfd1: bool = false,
    e0pd0: bool = false,
    e0pd1: bool = false,
    tcma0: bool = false,
    tcma1: bool = false,
    ds: bool = false,
    reserved2: u4 = 0,

    pub fn asInt(self: TcrReg) usize {
        return @bitCast(u64, self);
    }
};

pub fn PageTable(mapping: Mapping) !type {
    const page_size = mapping.granule.page_size;
    const table_size = try std.math.divExact(usize, page_size, 8);
    const max_lvl = mapping.granule.lvls_required;

    comptime var req_table_total = try board.boardConfig.calctotalTablesReq(mapping.granule, mapping.mem_size);

    return struct {
        const Self = @This();
        page_size: usize,
        table_size: usize,

        mapping: Mapping,
        max_lvl: TransLvl,
        map_pg_dir: *volatile [req_table_total][table_size]usize,

        pub fn init(base_addr: usize) !Self {
            return Self{
                // sizes
                .page_size = page_size,
                .table_size = table_size,

                .max_lvl = max_lvl,
                .mapping = mapping,
                .map_pg_dir = @intToPtr(*volatile [req_table_total][table_size]usize, base_addr),
            };
        }

        fn calcTransLvlDescriptorSize(self: *Self, lvl: TransLvl) usize {
            return std.math.pow(usize, self.table_size, @enumToInt(self.max_lvl) - @enumToInt(lvl)) * self.page_size;
        }

        pub fn mapMem(self: *Self) !void {
            var i_lvl: usize = 0;
            var to_map_in_descriptors: usize = 0;
            var table_offset: usize = 0;
            var phys_count_flags: TableDescriptorAttr = undefined;

            while (i_lvl <= @enumToInt(self.max_lvl)) : (i_lvl += 1) {
                switch (mapping.granule.page_size) {
                    Granule.Section.page_size => {
                        to_map_in_descriptors = try std.math.divExact(usize, mapping.mem_size, self.page_size);
                        phys_count_flags = mapping.flags.?;
                    },
                    else => {
                        to_map_in_descriptors = try std.math.divCeil(usize, self.mapping.mem_size, self.calcTransLvlDescriptorSize(@intToEnum(TransLvl, i_lvl)));
                        phys_count_flags = TableDescriptorAttr{ .accessPerm = .read_write, .descType = .page };
                    },
                }

                const to_map_in_tables = try std.math.divFloor(usize, to_map_in_descriptors, self.table_size);
                const rest_to_map_in_descriptors = try std.math.mod(usize, to_map_in_descriptors, self.table_size);

                const lvl_1_attr = (TableDescriptorAttr{ .accessPerm = .read_write, .descType = .block }).asInt();
                var phys_count = self.mapping.phys_addr | phys_count_flags.asInt();
                var i_table: usize = 0;
                var i_descriptors: usize = 0;
                // looping one table too far to write rest_to_map_in_descriptors which are leftover and accounted for in to_map_in_tables
                table_loop: while (i_table <= to_map_in_tables) : (i_table += 1) {
                    while (i_descriptors < self.table_size) : (i_descriptors += 1) {
                        // if last table is reached, only write the rest_to_map_in_descriptors
                        if (i_table == to_map_in_tables and i_descriptors > rest_to_map_in_descriptors)
                            break :table_loop;

                        // last lvl translation links to physical mem
                        if (i_lvl == @enumToInt(self.max_lvl)) {
                            self.map_pg_dir[table_offset + i_table][i_descriptors] = phys_count;
                            phys_count += self.mapping.granule.page_size;
                        } else {
                            // linking to next table...
                            self.map_pg_dir[table_offset + i_table][i_descriptors] = @ptrToInt(&self.map_pg_dir[table_offset + to_map_in_tables + i_descriptors]);
                            if (i_lvl == @enumToInt(TransLvl.first_lvl))
                                self.map_pg_dir[table_offset + i_table][i_descriptors] |= lvl_1_attr;
                        }
                    }
                    i_descriptors = 0;
                }
                table_offset += i_table + 1;
            }
        }
    };
}

pub inline fn toSecure(comptime T: type, inp: T) T {
    switch (@typeInfo(T)) {
        .Pointer => {
            return @intToPtr(T, @ptrToInt(inp) | board.config.mem.va_start);
        },
        .Int => {
            return inp | board.config.mem.va_start;
        },
        else => @compileError("mmu address translation: not supported type"),
    }
}

pub inline fn toUnsecure(comptime T: type, inp: T) T {
    switch (@typeInfo(T)) {
        .Pointer => {
            return @intToPtr(T, @ptrToInt(inp) & ~(board.config.mem.va_start));
        },
        .Int => {
            return inp & ~(board.config.mem.va_start);
        },
        else => @compileError("mmu address translation: not supported type"),
    }
}
