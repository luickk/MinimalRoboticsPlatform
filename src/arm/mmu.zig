const std = @import("std");
const board = @import("board");
const utils = @import("utils");
const kprint = @import("periph").uart.UartWriter(.ttbr1).kprint;

const ProccessorRegMap = @import("processor.zig").ProccessorRegMap;

const Granule = board.boardConfig.Granule;
const GranuleParams = board.boardConfig.Granule.GranuleParams;
const TransLvl = board.boardConfig.TransLvl;

pub const Mapping = struct {
    mem_size: usize,
    pointing_addr_start: usize,
    virt_addr_start: usize,
    granule: GranuleParams,
    addr_space: board.boardConfig.AddrSpace,
    // currently only supported for sections
    flags_last_lvl: TableDescriptorAttr,
    flags_non_last_lvl: TableDescriptorAttr,
};

const Error = error{
    FlagConfigErr,
    PageTableConfigErr,
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

    // 4 following are onl important for block entries
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
    address: u39 = 0,

    // indicating that the translation table descriptor is one of a contiguous set or descriptors, that might be cached in a single TLB descriptor
    contiguous: bool = false,
    // priviledeg execute-never bit. Determines whether the region is executable at EL1
    pxn: bool = false,
    // execute-never bit. Determines whether the region is executable
    uxn: bool = false,

    _padding2: u10 = 0,

    pub fn asInt(self: TableDescriptorAttr) usize {
        return @as(u64, @bitCast(self));
    }
};

pub fn PageTable(comptime total_mem_size: usize, comptime gran: GranuleParams) !type {
    comptime var req_table_total = try calctotalTablesReq(gran, total_mem_size);
    return struct {
        const Self = @This();
        pub const totaPageTableSize = req_table_total * gran.table_size;
        lma_offset: usize,
        total_size: usize,
        page_table_gran: GranuleParams,
        page_table: *volatile [req_table_total][gran.table_size]usize,

        pub fn init(page_tables: *volatile [req_table_total * gran.table_size]usize, lma_offset: usize) !Self {
            return Self{
                .lma_offset = lma_offset,
                .total_size = total_mem_size,
                .page_table_gran = gran,
                .page_table = @as(*volatile [req_table_total][gran.table_size]usize, @ptrCast(page_tables)),
            };
        }

        fn calcTransLvlDescriptorSize(mapping: Mapping, lvl: TransLvl) usize {
            return std.math.pow(usize, mapping.granule.table_size, @intFromEnum(mapping.granule.lvls_required) - @intFromEnum(lvl)) * mapping.granule.page_size;
        }

        pub fn mapMem(self: *Self, mapping_without_adjusted_flags: Mapping) !void {
            var mapping = mapping_without_adjusted_flags;
            if (std.meta.eql(mapping.granule, board.boardConfig.Granule.FourkSection)) mapping.flags_last_lvl.descType = .block;
            if (std.meta.eql(mapping.granule, board.boardConfig.Granule.Fourk)) mapping.flags_last_lvl.descType = .page;
            mapping.flags_non_last_lvl.descType = .page;

            if (!std.meta.eql(mapping.granule, gran)) return Error.PageTableConfigErr;

            var table_offset: usize = 0;
            var i_lvl: usize = 0;
            var phys_count = mapping.pointing_addr_start | mapping.flags_last_lvl.asInt();

            while (i_lvl <= @intFromEnum(mapping.granule.lvls_required)) : (i_lvl += 1) {
                const curr_lvl_desc_size = calcTransLvlDescriptorSize(mapping, @as(TransLvl, @enumFromInt(i_lvl)));
                var next_lvl_desc_size: usize = 0;
                var vas_next_offset_in_tables: usize = 0;
                if (i_lvl != @intFromEnum(mapping.granule.lvls_required)) {
                    next_lvl_desc_size = calcTransLvlDescriptorSize(mapping, @as(TransLvl, @enumFromInt(i_lvl + 1)));
                    vas_next_offset_in_tables = try std.math.divFloor(usize, try std.math.divExact(usize, mapping.virt_addr_start, next_lvl_desc_size), mapping.granule.table_size);
                }

                const vas_offset_in_descriptors = try std.math.divFloor(usize, mapping.virt_addr_start, curr_lvl_desc_size);
                const vas_offset_in_tables = try std.math.divFloor(usize, vas_offset_in_descriptors, mapping.granule.table_size);
                const vas_offset_in_descriptors_rest = try std.math.mod(usize, vas_offset_in_descriptors, mapping.granule.table_size);

                const to_map_in_descriptors = try std.math.divCeil(usize, mapping.mem_size + mapping.virt_addr_start, curr_lvl_desc_size);
                const to_map_in_tables = try std.math.divCeil(usize, to_map_in_descriptors, mapping.granule.table_size);
                const to_map_in_descriptors_rest = try std.math.mod(usize, to_map_in_descriptors, mapping.granule.table_size);

                const total_mem_size_padding_in_descriptors = try std.math.divFloor(usize, total_mem_size, curr_lvl_desc_size);
                var total_mem_size_padding_in_tables = try std.math.divFloor(usize, total_mem_size_padding_in_descriptors, mapping.granule.table_size);
                if (total_mem_size_padding_in_tables >= to_map_in_tables) total_mem_size_padding_in_tables -= to_map_in_tables;

                var i_table: usize = vas_offset_in_tables;
                var i_descriptor: usize = vas_offset_in_descriptors_rest;
                var left_descriptors: usize = 0;
                while (i_table < to_map_in_tables) : (i_table += 1) {
                    // if last table is reached, only write the to_map_in_descriptors_rest
                    left_descriptors = mapping.granule.table_size;
                    // explicitely casting to signed bc substraction could result in negative num.
                    if (i_table == @as(i128, to_map_in_tables - 1) and to_map_in_descriptors_rest != 0)
                        left_descriptors = to_map_in_descriptors_rest;

                    while (i_descriptor < left_descriptors) : (i_descriptor += 1) {
                        // last lvl translation links to physical mem
                        if (i_lvl == @intFromEnum(mapping.granule.lvls_required)) {
                            self.page_table[table_offset + i_table][i_descriptor] = phys_count;
                            phys_count += mapping.granule.page_size;
                        } else {
                            if (vas_next_offset_in_tables >= i_descriptor) vas_next_offset_in_tables -= i_descriptor;
                            var link_to_table_addr = utils.toTtbr0(usize, @intFromPtr(&self.page_table[table_offset + to_map_in_tables + i_descriptor + vas_next_offset_in_tables + total_mem_size_padding_in_tables])) + self.lma_offset;
                            if (i_lvl == @intFromEnum(TransLvl.first_lvl) or i_lvl == @intFromEnum(TransLvl.second_lvl))
                                link_to_table_addr |= mapping.flags_non_last_lvl.asInt();
                            self.page_table[table_offset + i_table][i_descriptor] = link_to_table_addr;
                        }
                    }
                    i_descriptor = 0;
                }
                table_offset += i_table + total_mem_size_padding_in_tables;
            }
        }
    };
}

fn calctotalTablesReq(comptime granule: Granule.GranuleParams, comptime mem_size: usize) !usize {
    const req_descriptors = try std.math.divExact(usize, mem_size, granule.page_size);

    var req_table_total_: usize = 0;
    var ci_lvl: usize = 1;
    while (ci_lvl <= @intFromEnum(granule.lvls_required) + 1) : (ci_lvl += 1) {
        req_table_total_ += try std.math.divCeil(usize, req_descriptors, std.math.pow(usize, granule.table_size, ci_lvl));
    }
    return req_table_total_;
}
