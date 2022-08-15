const addrMmu = @import("raspberryAddr.zig").Mmu;
const addrVmem = @import("raspberryAddr.zig").Vmem;

pub export const vaStart = addrVmem.vaStart;

pub export const physMemorySize = addrVmem.Values.physMemorySize;

pub export const pageMask = addrVmem.Values.pageMask;
pub export const pageShift = addrVmem.Values.pageShift;
pub export const tableShift = addrVmem.Values.tableShift;
pub export const sectionShift = addrVmem.Values.sectionShift;

pub export const pageSize = addrVmem.Values.pageSize;
pub export const sectionSize = addrVmem.Values.sectionSize;

pub export const lowMemory = addrVmem.Values.lowMemory;
pub export const highMemory = addrVmem.Values.highMemory;

pub export const pagingMemory = addrVmem.Values.pagingMemory;
pub export const pagingPages = addrVmem.Values.pagingPages;

pub export const ptrsPerTable = addrVmem.Values.ptrsPerTable;

pub export const pgdShift = addrVmem.Values.pgdShift;
pub export const pudShift = addrVmem.Values.pudShift;
pub export const pmdShift = addrVmem.Values.pmdShift;

pub export const pgDirSize = addrVmem.Values.pgDirSize;

// mmz
pub export const mmTypePageTable = addrMmu.Values.mmTypePageTable;
pub export const mmTypePage = addrMmu.Values.mmTypePage;
pub export const mmTypeBlock = addrMmu.Values.mmTypeBlock;
pub export const mmAccess = addrMmu.Values.mmAccess;
pub export const mmAccessPermission = addrMmu.Values.mmAccessPermission;

// Memory region attributes:
// n = AttrIndx[2:0]
// =    n   MAIR
// DEVICE_nGnRnE    000 00000000
// NORMAL_NC = 001  01000100
pub export const mtDeviceNGnRnE = addrMmu.Values.mtDeviceNGnRnE;
pub export const mtNormalNc = addrMmu.Values.mtNormalNc;
pub export const mtDeviceNGnRnEflags = addrMmu.Values.mtDeviceNGnRnEflags;
pub export const mtNormalNcFlags = addrMmu.Values.mtNormalNcFlags;
pub export const mairValue = addrMmu.Values.mairValue;

pub export const mmuFlags = addrMmu.Values.mmuFlags;
pub export const mmuDeviceFlags = addrMmu.Values.mmuDeviceFlags;
pub export const mmutPteFlags = addrMmu.Values.mmutPteFlags;

pub export const tcrT0sz = addrMmu.Values.tcrT0sz;
pub export const tcrT1sz = addrMmu.Values.tcrT1sz;
pub export const tcrTg04k = addrMmu.Values.tcrTg04k;
pub export const tcrTg14k = addrMmu.Values.tcrTg14k;
pub export const tcrValue = addrMmu.Values.tcrValue;
