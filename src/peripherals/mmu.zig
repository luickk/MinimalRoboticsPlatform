const std = @import("std");
const addr = @import("raspberryAddr.zig");
const addrMmu = @import("raspberryAddr.zig").Mmu;
const addrVmem = @import("raspberryAddr.zig").Vmem;
const kprint = @import("serial.zig").kprint;

pub const MmuFlags = struct {
    // mmu
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

    pub const BlockPopulationType = enum { section, page };
    // third (or fourth...) not required for the (currently) only supported granule
    pub const TransLvl = enum(usize) { first_lvl = 0, second_lvl = 1, third_lvl = 2 };

    pub const Mapping = struct { mem_size: usize, virt_start_addr: usize, phys_addr: usize };

    const Error = error{MemSizeTooBig};

    pub fn init(args: struct { base_addr: usize, page_shift: u6, table_shift: u6, mapping: Mapping }) !PageDir {
        const page_size = @as(usize, 1) << args.page_shift;
        const section_shift = args.page_shift + args.table_shift;
        const section_size = @as(usize, 1) << section_shift;

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
            .table_size = @as(usize, 1) << args.table_shift,

            .max_lvl = .third_lvl,
            .mapping = args.mapping,
            .table_base_addr = args.base_addr,
            .pg_dir = pg_dir,
        };
    }

    fn calcTransLvlEntrySize(self: *PageDir, lvl: TransLvl) usize {
        return std.math.pow(usize, self.table_size, @enumToInt(self.max_lvl) - @enumToInt(lvl)) * self.page_size;
    }

    // 1*512*512*4096
    // 512^(i-1)*4096
    pub fn mapMem(self: *PageDir) !void {
        // calc amounts of tables required per lvl
        var table_n = [_]usize{0} ** 3;
        var i: usize = 0;
        while (i <= @enumToInt(self.max_lvl)) : (i += 1) {
            table_n[i] = try std.math.divCeil(usize, self.mapping.mem_size, self.calcTransLvlEntrySize(@intToEnum(TransLvl, i)));
        }
        var base_dir_offset = toUnsecure(usize, @ptrToInt(self.pg_dir.ptr));
        i = 0;
        var phys_count = self.mapping.phys_addr | MmuFlags.mmTypePageTable;
        var table_complete_offset: usize = 0;

        while (i <= @enumToInt(self.max_lvl)) : (i += 1) {
            var j: usize = 1;
            // kprint("i: {d} ({d})\n", .{ i, tables });
            while (j <= table_n[i]) : (j += 1) {
                // last lvl translation links to physical mem
                if (i == @enumToInt(self.max_lvl)) {
                    self.pg_dir[table_complete_offset + j] = phys_count;
                    phys_count += self.page_size;
                    // trans layer before link to next tables
                } else {
                    self.pg_dir[table_complete_offset + j] = (base_dir_offset + table_complete_offset + table_n[i] + j * self.table_size) | MmuFlags.mmTypePageTable;
                }
            }
            table_complete_offset = self.table_size - table_n[i];
        }

        i = 0;
        while (i <= 2000) : (i += 1) {
            kprint("{d}: {d}\n", .{ i, @intToPtr(*u64, base_dir_offset + i * 8).* });
        }
    }

    // populates a Page Table with physical adresses aka. sections or pages
    pub fn populateTableWithPhys(self: *PageDir, args: struct { trans_lvl: TransLvl, pop_type: BlockPopulationType, mapping: Mapping, flags: usize }) !void {
        var shift: u6 = undefined;
        var step_size: usize = undefined;

        switch (args.pop_type) {
            .section => {
                shift = self.section_shift;
                step_size = self.section_size;
            },
            .page => {
                shift = self.page_shift;
                step_size = self.page_size;
            },
        }

        var phys_count = args.mapping.phys_addr | args.flags;
        // phys_count >>= shift;
        // phys_count |= phys_shifted;

        var i: usize = args.mapping.virt_start_addr;
        i = toUnsecure(usize, i);
        i = try std.math.divCeil(usize, i, step_size);

        var i_max: usize = args.mapping.virt_start_addr + args.mapping.mem_size;
        i_max = toUnsecure(usize, i_max) - toUnsecure(usize, args.mapping.virt_start_addr);
        i_max = try std.math.divCeil(usize, i_max, step_size);

        while (i <= i_max) : (i += 1) {
            self.pg_dir[@enumToInt(args.trans_lvl) * self.table_size + i] = phys_count;
            phys_count += step_size;
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
