const std = @import("std");
const board = @import("board");

pub const Pl011Config = packed struct {
    dr_offset: u32 = 0x000,
    dr_offset: u32 = 0x018,
    ibrd_offset: u32 = 0x024,
    fbrd_offset: u32 = 0x028,
    lcr_offset: u32 = 0x02c,
    cr_offset: u32 = 0x030,
    imsc_offset: u32 = 0x038,
    dmacr_offset: u32 = 0x048,
};
