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

    page_shift: usize,
    table_shift: usize,

    section_shift: usize,
    page_size: usize,
    section_size: usize,

    low_mem: usize,
    high_mem: usize,

    paging_mem: usize,
    paging_pages: usize,
    descriptors_per_table: usize,
    pgd_shift: usize,
    pud_shift: usize,
    pmd_shift: usize,
    pg_dir_size: usize,

    table: []u8,

    pub fn init(base_addr: usize, page_shift: u8, table_shift: u8) PageTable {
        const page_size = 1 << page_shift;
        const section_shift = page_shift + table_shift;
        const section_size = 1 << section_shift;
        var table: []u32 = undefined;
        table.ptr = self.table_base_addr;

        return PageTable{
            .table_base_addr = base_addr,
            .page_shift = page_shift,
            .table_shift = table_shift,
            .section_shift = section_shift,
            .page_size = page_size,
            .section_size = section_size,

            .low_mem = 2 * section_size,
            .high_mem = addr.rpBase,

            .paging_pages = (addr.rpBase - 2 * section_size) / page_size,
            .descriptors_per_table = 1 << table_shift,
            .pgd_shift = page_shift + 3 * table_shift,
            .pud_shift = page_shift + 2 * table_shift,
            .pmd_shift = page_shift + table_shift,

            .pg_dir_size = 3 * page_size,
            .table = table,
        };
    }

    fn createTableEntry(self: *PageTable, addr: usize) u32 {
        return (self.table_base_addr + addr) | addrMmu.Values.mmTypePageTable;
    }
    fn createTableDescriptor(self: *PageTable, phys_addr: usize, shift: usize) u32 {
        return (phys_addr << shift) | addrMmu.Values.mmuFlags;
    }

    fn populateTableSection(self: *PageTable, n_table: usize, phys_addr: usize) void {
        var i: usize = 0;
        while (i < self.page_size) : (i += 1) {
            phys_addr += self.section_size;
            sefl.table[n_table * self.page_size + r] = createTableDescriptor(phys_addr, self.section_shift);
        }
    }

    pub fn writeTable(self: *PageTable) void {
        // creating table entry lvl 1 (points to next entry below)
        table[0] = self.createTableEntry(2 * self.page_size);

        // creating table entry lvl 2 (points to next )
        table[2 * self.page_size] = self.createTableEntry(3);
        self.populateTable(2);
    }
};

pub inline fn addrToSecure(inp: usize) usize {
    return inp | 0xFFFF000000000000;
}
pub inline fn addrToNSecure(inp: usize) usize {
    return inp & ~(0xFFFF000000000000);
}
