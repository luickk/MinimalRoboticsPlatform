const std = @import("std");
const addr = @import("raspberryAddr.zig");
const addrMmu = @import("raspberryAddr.zig").Mmu;
const addrVmem = @import("raspberryAddr.zig").Vmem;
const bprint = @import("serial.zig").bprint;

const Error = error{AddrTypeNotSupported};

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

pub const PageDir = struct {
    table_base_addr: usize,

    page_shift: u6,
    table_shift: u6,
    section_shift: u6,

    page_size: usize,
    section_size: usize,

    descriptors_per_table: usize,
    pg_dir: []volatile usize,

    pub const BlockPopulationType = enum { section, page };
    pub const TransLvl = enum(usize) { first_lvl = 0, second_lvl = 1, third_lvl = 2, fourth_lvl = 3 };

    pub fn init(args: struct { base_addr: usize, page_shift: u6, table_shift: u6 }) !PageDir {
        const page_size = @as(usize, 1) << args.page_shift;
        const section_shift = args.page_shift + args.table_shift;
        const section_size = @as(usize, 1) << section_shift;

        var pg_dir: []volatile usize = undefined;
        pg_dir.ptr = @intToPtr([*]usize, args.base_addr);
        // max 4 pages -> u64 array -> x / 8
        pg_dir.len = try std.math.divExact(usize, 4 * page_size, 8);

        return PageDir{
            .table_base_addr = args.base_addr,
            // shifts
            .page_shift = args.page_shift,
            .table_shift = args.table_shift,
            .section_shift = section_shift,

            // sizes
            .page_size = page_size,
            .section_size = section_size,

            .descriptors_per_table = @as(usize, 1) << args.table_shift,
            .pg_dir = pg_dir,
        };
    }

    // a pg_dir entry always points to a next lvl pg_dir addr
    pub fn newTransLvl(self: *PageDir, trans_lvl: TransLvl, virt_start_addr: usize, flags: ?usize) void {
        var fflags = flags orelse 0;
        // lsr \tmp1, \virt, #\shift
        // and \tmp1, \tmp1, #PTRS_PER_TABLE - 1
        var start_va = virt_start_addr;
        start_va >>= @truncate(u6, self.page_shift + ((3 - @enumToInt(trans_lvl)) * self.table_shift));
        start_va &= self.descriptors_per_table - 1;
        // ! use descriptors_per_table for pg_dir slice index and pagesize for newTableEntry (since the latter is in bytes and the pg_dir slice index in usize)
        self.pg_dir[@enumToInt(trans_lvl) * self.descriptors_per_table] = (self.table_base_addr + ((@enumToInt(trans_lvl) + 1) * self.page_size)) | fflags;
    }

    // newBlock populates block PageDir in a certain translation pg_dir lvl
    pub fn populateTransLvl(self: *PageDir, args: struct { trans_lvl: TransLvl, pop_type: BlockPopulationType, virt_start_addr: usize, virt_end_addr: usize, phys_addr: usize, flags: usize }) void {
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

        var phys_count = args.phys_addr;
        phys_count >>= shift;
        phys_count |= args.flags;

        var i: usize = args.virt_start_addr;
        i >>= shift;
        i &= self.descriptors_per_table - 1;

        var i_max: usize = args.virt_end_addr;
        i_max >>= shift;
        i_max &= (self.descriptors_per_table - 1);

        while (i <= i_max) : (i += 1) {
            self.pg_dir[@enumToInt(args.trans_lvl) * self.descriptors_per_table + i] = phys_count;
            phys_count += step_size;
        }
    }

    pub fn zeroPgDir(self: *PageDir) void {
        for (self.pg_dir) |*e| {
            e.* = 0x0;
        }
    }
};

pub inline fn toSecure(comptime T: type, inp: T) !T {
    switch (@typeInfo(T)) {
        .Pointer => {
            return @intToPtr(T, @ptrToInt(inp) | 0xFFFF000000000000);
        },
        .Int => {
            return inp | 0xFFFF000000000000;
        },
        else => {
            return Error.AddrTypeNotSupported;
        },
    }
}

pub inline fn toUnsecure(comptime T: type, inp: T) !T {
    switch (@typeInfo(T)) {
        .Pointer => {
            return @intToPtr(T, @ptrToInt(inp) & ~(0xFFFF000000000000));
        },
        .Int => {
            return inp & ~(0xFFFF000000000000);
        },
        else => {
            return Error.AddrTypeNotSupported;
        },
    }
}
