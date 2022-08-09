pub fn irq_handler() callconv(.C) void {}
pub fn irq_elx_spx() callconv(.C) void {}

// identifiers for the vector table ic_handler call
pub export const EL1_SYNC: u64 = 0x1;
pub export const EL1_IRQ: u64 = 0x2;
pub export const EL1_FIQ: u64 = 0x3;
pub export const EL1_ERR: u64 = 0x4;
pub export const ELX_SPX: u64 = 0x5;
