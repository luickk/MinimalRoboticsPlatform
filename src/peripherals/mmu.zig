const std = @import("std");
const addr = @import("raspberryAddr.zig");
const addrMmu = @import("raspberryAddr.zig").Mmu;
const addrVmem = @import("raspberryAddr.zig").Vmem;
const kprint = @import("serial.zig").kprint;

// In addition to an output address, a translation table entry that refers to a page or region of memory
// includes fields that define properties of the target memory region. These fields can be classified as
// address map control, access control, and region attribute fields.
pub const TableEntryAttr = packed struct {
    // block indicates next trans lvl (or physical for sections) and page the last trans lvl (with physical addr)
    pub const DescType = enum(u1) { block = 0, page = 1 };
    // redirects read from mem tables to mairx reg
    pub const AttrIndex = enum(u3) { mair0 = 0, mair1 = 1 };
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
    attrIndex: AttrIndex = .mair1,
    // For memory accesses from Secure state, specifies whether the output address is in the Secure or Non-secure address map
    ns: bool = false,
    // depends on translation level (Stage2AccessPerm, Stage1AccessPerm, SecureAccessPerm)
    accessPerm: Stage1AccessPerm = .read_only,
    sharableAttr: Sharability = .non_sharable,

    // The access flag indicates when a page or section of memory is accessed for the first time since the
    // Access flag in the corresponding translation table descriptor was set to 0.
    accessFlag: bool = true,
    // the not global bit. Determines whether the TLB entry applies to all ASID values, or only to the current ASID value
    notGlobal: bool = false,

    _padding: u39 = 0,

    // indicating that the translation table entry is one of a contiguous set or entries, that might be cached in a single TLB entry
    contiguous: bool = false,
    // priviledeg execute-never bit. Determines whether the region is executable at EL1
    pxn: bool = false,
    // execute-never bit. Determines whether the region is executable
    uxn: bool = false,

    _padding2: u10 = 0,

    pub fn asInt(self: TableEntryAttr) usize {
        return @bitCast(u64, self);
    }
};

pub const MmuFlags = struct {
    pub const mmTypePageTable: usize = 0x3;
    pub const mmTypePage: usize = 0x3;
    pub const mmTypeBlock: usize = 0x1;
    pub const mmAccess: usize = (0x1 << 10);
    pub const mmAccessPermission: usize = (0x01 << 6);

    pub const mtDeviceNGnRnE: usize = 0x0;
    pub const mtNormalNc: usize = 0x1;
    pub const mtDeviceNGnRnEflags: usize = 0x00;
    pub const mtNormalNcFlags: usize = 0x44;
    pub const mairValue: usize = (mtDeviceNGnRnEflags << (8 * mtDeviceNGnRnE)) | (mtNormalNcFlags << (8 * mtNormalNc));

    pub const mmuFlags: usize = (mmTypeBlock | (mtNormalNc << 2) | mmAccess);
    pub const mmuDeviceFlags: usize = (mmTypeBlock | (mtDeviceNGnRnE << 2) | mmAccess);
    pub const mmutPteFlags: usize = (mmTypePageTable | (mtNormalNc << 2) | mmAccess | mmAccessPermission);

    pub const tcrT0sz: usize = (64 - 48);
    pub const tcrT1sz: usize = ((64 - 48) << 16);
    pub const tcrTg04k = (0 << 14);
    pub const tcrTg14k: usize = (2 << 30);
    pub const tcrValue: usize = (tcrT0sz | tcrT1sz | tcrTg04k | tcrTg14k);
};
export const _mairVal = MmuFlags.mairValue;
export const _tcrVal = MmuFlags.tcrValue;

// only 4096 granule (yet)
pub const PageDir = struct {
    table_base_addr: usize,

    page_shift: u6,
    table_shift: u6,
    section_shift: u6,

    page_size: usize,
    section_size: usize,

    mapping: Mapping,
    max_lvl: TransLvl,
    table_size: usize,
    pg_dir: []volatile usize,
    // todo => replace 512 with comptime table_size
    map_pg_dir: []volatile [512]usize,

    // third (or fourth...) not required for the (currently) only supported granule
    pub const TransLvl = enum(usize) { first_lvl = 0, second_lvl = 1, third_lvl = 2 };

    pub const Mapping = struct { mem_size: usize, virt_start_addr: usize, phys_addr: usize };

    const Error = error{MemSizeTooBig};

    pub fn init(args: struct { base_addr: usize, page_shift: u6, table_shift: u6, mapping: Mapping }) !PageDir {
        const page_size = @as(usize, 1) << args.page_shift;
        const section_shift = args.page_shift + args.table_shift;
        const section_size = @as(usize, 1) << section_shift;
        const table_size = @as(usize, 1) << args.table_shift;
        var map_pg_dir: []volatile [512]usize = undefined;
        map_pg_dir.ptr = @intToPtr([*]volatile [512]usize, args.base_addr);
        map_pg_dir.len = 512 * page_size;

        var pg_dir: []volatile usize = undefined;
        pg_dir.ptr = @intToPtr([*]usize, args.base_addr);

        // todo => set to proper length
        // pg_dir.len = try std.math.divExact(usize, 512 * page_size, 8);
        return PageDir{
            // shifts
            .page_shift = args.page_shift,
            .table_shift = args.table_shift,
            .section_shift = section_shift,

            // sizes
            .page_size = page_size,
            .section_size = section_size,
            .table_size = table_size,

            .max_lvl = .third_lvl,
            .mapping = args.mapping,
            .table_base_addr = args.base_addr,
            .pg_dir = pg_dir,
            .map_pg_dir = map_pg_dir,
        };
    }

    fn calcTransLvlEntrySize(self: *PageDir, lvl: TransLvl) usize {
        return std.math.pow(usize, self.table_size, @enumToInt(self.max_lvl) - @enumToInt(lvl)) * self.page_size;
    }

    // 1*512*512*4096
    // 512^(i-1)*4096
    pub fn mapMem(self: *PageDir) !void {
        // calc amounts of tables required per lvl
        var table_entries = [_]usize{0} ** 3;
        var curr_lvl: usize = 0;
        const lvl_1_2_attr = (TableEntryAttr{ .accessPerm = .read_write, .descType = .block }).asInt();
        kprint("lvl_1_2_attr: {b} \n", .{lvl_1_2_attr});
        kprint("ssss: {b} \n", .{MmuFlags.mmuFlags});

        while (curr_lvl <= @enumToInt(self.max_lvl)) : (curr_lvl += 1) {
            // todo => print required for table_entries[1] not to be 0???????????
            kprint("s: {d} \n", .{try std.math.divCeil(usize, self.mapping.mem_size, self.calcTransLvlEntrySize(@intToEnum(TransLvl, curr_lvl)))});
            table_entries[curr_lvl] = try std.math.divCeil(usize, self.mapping.mem_size, self.calcTransLvlEntrySize(@intToEnum(TransLvl, curr_lvl)));
        }

        curr_lvl = 0;
        var phys_count = self.mapping.phys_addr | (TableEntryAttr{ .accessPerm = .read_write, .descType = .page }).asInt();
        var pg_dir_offset: usize = 0;
        while (curr_lvl <= @enumToInt(self.max_lvl)) : (curr_lvl += 1) {
            var req_table = (try std.math.divCeil(usize, table_entries[curr_lvl], self.table_size));
            var req_entry: usize = table_entries[curr_lvl];
            var curr_entry: usize = 0;
            var curr_table: usize = 0;
            while (curr_table < req_table) : (curr_table += 1) {
                curr_entry = 0;
                if (req_entry > self.table_size)
                    req_entry -= self.table_size;
                while (curr_entry <= self.table_size) : (curr_entry += 1) {
                    // kprint("{d} {d} \n", .{ curr_lvl, curr_entry });
                    // last lvl translation links to physical mem
                    if (curr_lvl == @enumToInt(self.max_lvl)) {
                        self.map_pg_dir[pg_dir_offset + curr_table][curr_entry] = phys_count;
                        phys_count += self.page_size;
                        // trans layer before link to next tables
                    } else {
                        self.map_pg_dir[pg_dir_offset + curr_table][curr_entry] = @ptrToInt(&self.map_pg_dir[pg_dir_offset + req_table + curr_entry]) | lvl_1_2_attr;
                    }
                    if (req_entry < self.table_size)
                        break;
                }
            }
            pg_dir_offset += req_table;
        }
        // kprint("base address: {*} \n", .{self.map_pg_dir.ptr});
        // kprint("1 lvl (1 table entry): {*} 0x{x} \n", .{ &self.map_pg_dir[0][0], self.map_pg_dir[0][0] });
        // kprint("------- \n", .{});
        // kprint("2 lvl (2 table entry): {*} 0x{x} \n", .{ &self.map_pg_dir[1][0], self.map_pg_dir[1][0] });
        // kprint("2 lvl (2 table entry): {*} 0x{x} \n", .{ &self.map_pg_dir[1][1], self.map_pg_dir[1][1] });
        // kprint("2 lvl (2 table entry): {*} 0x{x} \n", .{ &self.map_pg_dir[1][2], self.map_pg_dir[1][2] });
        // kprint("------- \n", .{});
        // kprint("3 lvl (3 table base address!): {*} 0x{x} \n", .{ &self.map_pg_dir[2][0], self.map_pg_dir[2][0] });
        // kprint("3 lvl (4 table base address!): {*} 0x{x} \n", .{ &self.map_pg_dir[3][0], self.map_pg_dir[3][0] });
        // kprint("3 lvl (5 table base address!): {*} 0x{x} \n", .{ &self.map_pg_dir[4][0], self.map_pg_dir[4][0] });

        kprint("done loop \n", .{});
    }

    // populates a Page Table with physical adresses aka. sections or pages
    pub fn createSection(self: *PageDir, trans_lvl: TransLvl, mapping: Mapping, flags: TableEntryAttr) !void {
        var phys_count = mapping.phys_addr | flags.asInt();
        // phys_count >>= shift;
        // phys_count |= phys_shifted;

        var i: usize = mapping.virt_start_addr;
        i = toUnsecure(usize, i);
        i = try std.math.divCeil(usize, i, self.section_size);

        var i_max: usize = mapping.virt_start_addr + mapping.mem_size;
        i_max = toUnsecure(usize, i_max) - toUnsecure(usize, mapping.virt_start_addr);
        i_max = try std.math.divCeil(usize, i_max, self.section_size);

        while (i <= i_max) : (i += 1) {
            self.pg_dir[@enumToInt(trans_lvl) * self.table_size + i] = phys_count;
            phys_count += self.section_size;
        }
    }

    pub fn zeroPgDir(self: *PageDir) void {
        for (self.pg_dir) |*e| {
            e.* = 0x0;
        }
    }
};

pub inline fn toSecure(comptime T: type, inp: T) T {
    switch (@typeInfo(T)) {
        .Pointer => {
            return @intToPtr(T, @ptrToInt(inp) | addr.vaStart);
        },
        .Int => {
            return inp | addr.vaStart;
        },
        else => @compileError("mmu address translation: not supported type"),
    }
}

pub inline fn toUnsecure(comptime T: type, inp: T) T {
    switch (@typeInfo(T)) {
        .Pointer => {
            return @intToPtr(T, @ptrToInt(inp) & ~(addr.vaStart));
        },
        .Int => {
            return inp & ~(addr.vaStart);
        },
        else => @compileError("mmu address translation: not supported type"),
    }
}
