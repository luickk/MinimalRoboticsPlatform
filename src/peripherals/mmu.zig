const std = @import("std");
const addr = @import("raspberryAddr.zig");
const addrMmu = @import("raspberryAddr.zig").Mmu;
const addrVmem = @import("raspberryAddr.zig").Vmem;
const kprint = @import("serial.zig").kprint;

export const vaStart = addr.vaStart;

export const physMemorySize = addrVmem.Values.physMemorySize;

export const pageMask = addrVmem.Values.pageMask;
export const pageShift = addrVmem.Values.pageShift;
export const tableShift = addrVmem.Values.tableShift;
export const sectionShift = addrVmem.Values.sectionShift;

export const pageSize = addrVmem.Values.pageSize;
export const sectionSize = addrVmem.Values.sectionSize;

export const lowMemory = addrVmem.Values.lowMemory;
export const highMemory = addrVmem.Values.highMemory;

export const pagingMemory = addrVmem.Values.pagingMemory;
export const pagingPages = addrVmem.Values.pagingPages;

export const ptrsPerTable = addrVmem.Values.ptrsPerTable;

export const pgdShift = addrVmem.Values.pgdShift;
export const pudShift = addrVmem.Values.pudShift;
export const pmdShift = addrVmem.Values.pmdShift;

export const pgDirSize = addrVmem.Values.pgDirSize;
export const mmTypePageTable = addrMmu.Values.mmTypePageTable;
export const mmTypePage = addrMmu.Values.mmTypePage;
export const mmTypeBlock = addrMmu.Values.mmTypeBlock;
export const mmAccess = addrMmu.Values.mmAccess;
export const mmAccessPermission = addrMmu.Values.mmAccessPermission;
export const mtDeviceNGnRnE = addrMmu.Values.mtDeviceNGnRnE;
export const mtNormalNc = addrMmu.Values.mtNormalNc;
export const mtDeviceNGnRnEflags = addrMmu.Values.mtDeviceNGnRnEflags;
export const mtNormalNcFlags = addrMmu.Values.mtNormalNcFlags;
export const mairValue = addrMmu.Values.mairValue;

export const mmuFlags = addrMmu.Values.mmuFlags;
export const mmuDeviceFlags = addrMmu.Values.mmuDeviceFlags;
export const mmutPteFlags = addrMmu.Values.mmutPteFlags;

export const tcrT0sz = addrMmu.Values.tcrT0sz;
export const tcrT1sz = addrMmu.Values.tcrT1sz;
export const tcrTg04k = addrMmu.Values.tcrTg04k;
export const tcrTg14k = addrMmu.Values.tcrTg14k;
export const tcrValue = addrMmu.Values.tcrValue;

extern const _pg_dir: u8;

pub const PageTable = struct {
    table_base_addr: usize,

    page_shift: u6,
    table_shift: u6,

    section_shift: u6,
    page_size: usize,
    section_size: usize,

    low_mem: usize,
    high_mem: usize,

    paging_pages: usize,
    descriptors_per_table: usize,
    pgd_shift: u6,
    pud_shift: u6,
    pmd_shift: u6,
    pg_dir_size: usize,

    table: [*]u32,

    pub const BlockPopulationType = enum { sections, pages };
    pub const TransLvl = enum { first, second, third };

    pub fn init(base_addr: usize, page_shift: u6, table_shift: u6) PageTable {
        const page_size = @as(usize, 1) << page_shift;
        const section_shift: u6 = page_shift + table_shift;
        const section_size = @as(usize, 1) << section_shift;
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
            .paging_pages = (addr.rpBase - 2 * section_size) / page_size,
            .descriptors_per_table = @as(usize, 1) << table_shift,

            // memory
            .low_mem = 2 * section_size,
            .high_mem = addr.rpBase,
            .table = @intToPtr([*]u32, base_addr),
        };
    }

    // a table entry always points to a next lvl table addr
    fn newTableEntry(self: *PageTable, pointing_to_addr: usize) u32 {
        return @truncate(u32, (self.table_base_addr + pointing_to_addr) | addrMmu.Values.mmTypePageTable);
    }

    // describes a block of memory, depending on granule
    fn newBlockEntry(phys_addr: usize, shift: u6) u32 {
        return @truncate(u32, (phys_addr << shift) | addrMmu.Values.mmuFlags);
    }

    // newBlock populates block entries in a certain translation table lvl
    fn newBlock(self: *PageTable, pg_table_addr: usize, virt_start_addr: usize, virt_end_addr: usize, phys_addr: usize, shift: u6) void {
        var phys_count = phys_addr;
        var i: usize = virt_start_addr;
        while (i < virt_end_addr) : (i += 1) {
            self.table[pg_table_addr + virt_start_addr + i] = newBlockEntry(phys_count, shift);
            phys_count += self.section_size;
        }
    }

    fn zeroPgDir(self: *PageTable) void {
        var i: usize = 0;
        while (i < self.pg_dir_size) : (i += 1) {
            // self.table[i] = 0xFFFFFFFF;
            // el.* = 0xFFFFFFFF;
            @intToPtr(*u32, 0xb000 + i).* = 0xFFFFFFFF;
        }
    }
    pub fn writeTable(self: *PageTable) void {
        kprint("table addr: {x}, size: {d} \n", .{ @ptrToInt(self.table), self.pg_dir_size });
        self.zeroPgDir();

        kprint("text: {x} \n", .{self.page_size});
        // creating table entry lvl 1 (points to next entry below)
        self.table[0] = self.newTableEntry(1 * self.page_size);

        // next entry
        self.table[1 * self.page_size] = self.newTableEntry(2 * self.page_size);

        self.newBlock(2 * self.page_size, 0, 0x40000000, 0, self.section_shift);
    }
};

pub inline fn addrToSecure(inp: usize) usize {
    return inp | 0xFFFF000000000000;
}
pub inline fn addrToNSecure(inp: usize) usize {
    return inp & ~(0xFFFF000000000000);
}
