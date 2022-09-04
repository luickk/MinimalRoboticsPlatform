const std = @import("std");
const addr = @import("raspberryAddr.zig");
const addrMmu = @import("raspberryAddr.zig").Mmu;
const addrVmem = @import("raspberryAddr.zig").Vmem;
const bprint = @import("serial.zig").bprint;

const Error = error{AddrTypeNotSupported};

pub const PageTable = struct {
    table_base_addr: usize,

    page_shift: u5,
    table_shift: u5,

    section_shift: u5,
    page_size: u64,
    section_size: u64,

    low_mem: u64,
    high_mem: u64,

    paging_pages: u64,
    descriptors_per_table: u64,
    pgd_shift: u5,
    pud_shift: u5,
    pmd_shift: u5,
    pg_dir_size: u64,

    table: []volatile u64,

    pub const BlockPopulationType = enum { section, page };
    pub const TransLvl = enum { first, second, third };

    pub fn init(base_addr: usize, page_shift: u5, table_shift: u5) !PageTable {
        const page_size = @as(u64, 1) << page_shift;
        const section_shift: u5 = page_shift + table_shift;
        const section_size = @as(u64, 1) << section_shift;
        const pg_dir_size = 3 * page_size;
        var table: []volatile u64 = undefined;
        table.ptr = @intToPtr([*]u64, base_addr);
        table.len = try std.math.divExact(u64, pg_dir_size, 4);

        return PageTable{
            .table_base_addr = base_addr,

            // shifts
            .page_shift = page_shift,
            .table_shift = table_shift,
            .section_shift = section_shift,

            .pgd_shift = page_shift + 3 * table_shift,
            .pud_shift = page_shift + 2 * table_shift,
            .pmd_shift = page_shift + table_shift,

            // sizes
            .page_size = page_size,
            .section_size = section_size,
            .pg_dir_size = pg_dir_size,

            // n
            .paging_pages = (@truncate(u64, addr.rpBase) - 2 * section_size) / page_size,
            .descriptors_per_table = @as(u64, 1) << table_shift,

            // memory
            .low_mem = 2 * section_size,
            .high_mem = addr.rpBase,
            .table = table,
        };
    }

    // a table entry always points to a next lvl table addr
    fn newTableEntry(self: *PageTable, pointing_to_addr: u64) u64 {
        return @truncate(u64, (self.table_base_addr + pointing_to_addr) | addrMmu.Values.mmTypePageTable);
    }

    // newBlock populates block entries in a certain translation table lvl
    fn popTableEntry(self: *PageTable, pg_table_addr: u64, virt_start_addr: u64, virt_end_addr: u64, phys_addr: u64, flags: u64, pop_type: BlockPopulationType) void {
        var shift: u5 = undefined;
        var step_size: u64 = undefined;

        switch (pop_type) {
            .section => {
                shift = self.section_shift;
                step_size = self.section_size;
            },
            .page => {
                shift = self.page_shift;
                step_size = self.page_size;
            },
        }

        var phys_count = phys_addr;
        phys_count >>= shift;
        phys_count |= flags;

        var i: usize = virt_start_addr;
        i >>= shift;
        i &= self.descriptors_per_table - 1;

        var i_max: usize = virt_end_addr;
        i_max >>= shift;
        i_max &= (self.descriptors_per_table - 1);

        bprint("i: {d}, i_max: {d}, phys: {d} \n", .{ i, i_max, phys_count });
        while (i <= i_max) : (i += 1) {
            self.table[pg_table_addr + i] = phys_count;
            phys_count += step_size;
        }
    }

    fn zeroPgDir(self: *PageTable) void {
        for (self.table) |*e| {
            e.* = 0x0;
        }
    }
    pub fn writeTable(self: *PageTable) void {
        self.zeroPgDir();

        // ! use descriptors_per_table for table slice index and pagesize for newTableEntry (since the latter is in bytes and the table slice index in u64)

        // creating table entry lvl 1 (points to next entry below)
        self.table[0] = self.newTableEntry(1 * self.page_size);

        // next entry
        self.table[self.descriptors_per_table * 1] = self.newTableEntry(2 * self.page_size);

        // identity mapped!
        self.popTableEntry(self.descriptors_per_table * 2, 0, 18446462599804485632, 0, addrMmu.Values.mmuFlags, .section);
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
