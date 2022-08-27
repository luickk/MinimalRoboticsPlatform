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

pub inline fn kernelPh2Virt(inp: usize) usize {
    return inp | 0xFFFF000000000000;
}
