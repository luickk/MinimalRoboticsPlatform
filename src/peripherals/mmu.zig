const std = @import("std");
const addr = @import("raspberryAddr.zig");
const addrMmu = @import("raspberryAddr.zig").Mmu;
const addrVmem = @import("raspberryAddr.zig").Vmem;
const kprint = @import("serial.zig").kprint;

pub const PageTable = struct {
    table_base_addr: usize,

    page_shift: u5,
    table_shift: u5,

    section_shift: u5,
    page_size: u32,
    section_size: u32,

    low_mem: u32,
    high_mem: u32,

    paging_pages: u32,
    descriptors_per_table: u32,
    pgd_shift: u5,
    pud_shift: u5,
    pmd_shift: u5,
    pg_dir_size: u32,

    table: [*]u32,

    pub const BlockPopulationType = enum { section, page };
    pub const TransLvl = enum { first, second, third };

    pub fn init(base_addr: usize, page_shift: u5, table_shift: u5) PageTable {
        const page_size = @as(u32, 1) << page_shift;
        const section_shift: u5 = page_shift + table_shift;
        const section_size = @as(u32, 1) << section_shift;
        const pg_dir_size = 3 * page_size;

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
            .paging_pages = (@truncate(u32, addr.rpBase) - 2 * section_size) / page_size,
            .descriptors_per_table = @as(u32, 1) << table_shift,

            // memory
            .low_mem = 2 * section_size,
            .high_mem = addr.rpBase,
            .table = @intToPtr([*]u32, base_addr),
        };
    }

    // a table entry always points to a next lvl table addr
    fn newTableEntry(self: *PageTable, pointing_to_addr: u32) u32 {
        return @truncate(u32, (self.table_base_addr + pointing_to_addr) | addrMmu.Values.mmTypePageTable);
    }

    // newBlock populates block entries in a certain translation table lvl
    fn popTableEntry(self: *PageTable, pg_table_addr: u32, virt_start_addr: u32, virt_end_addr: u32, phys_addr: u32, flags: u32, pop_type: BlockPopulationType) void {
        var shift: u5 = undefined;
        var step_size: u32 = undefined;

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
        phys_count |= phys_count << shift;

        var i: usize = virt_start_addr;
        i >>= shift;
        i &= self.descriptors_per_table - 1;

        var i_max: usize = virt_end_addr;
        i >>= shift;
        i &= self.descriptors_per_table - 1;

        while (i < i_max) : (i += 1) {
            self.table[pg_table_addr + i] = phys_count;
            phys_count += step_size;
        }
    }

    fn zeroPgDir(self: *PageTable) void {
        var i: usize = 0;
        while (i < self.pg_dir_size) : (i += 1) {
            self.table[i] = 0x0;
        }
    }
    pub fn writeTable(self: *PageTable) void {
        kprint("table addr: {x}, size: {d} \n", .{ @ptrToInt(self.table), self.descriptors_per_table });
        self.zeroPgDir();

        // ! use descriptors_per_table for table slice index and pagesize for newTableEntry (since the latter is in bytes and the table slice index in 32bit uints)

        // creating table entry lvl 1 (points to next entry below)
        self.table[self.descriptors_per_table * 0] = self.newTableEntry(2 * self.page_size);
        // @intToPtr(*u32, self.table_base_addr + 1).* = self.newTableEntry(1 * self.page_size);

        // next entry
        self.table[self.descriptors_per_table * 2] = self.newTableEntry(4 * self.page_size);
        // @intToPtr(*u32, self.table_base_addr + self.page_size).* = self.newTableEntry(2 * self.page_size);

        // identity mapped!
        self.popTableEntry(self.descriptors_per_table * 4, 0, 502404, 0, addrMmu.Values.mmuFlags, .section);
    }
};

pub inline fn addrToSecure(inp: usize) usize {
    return inp | 0xFFFF000000000000;
}
pub inline fn addrToNSecure(inp: usize) usize {
    return inp & ~(0xFFFF000000000000);
}
