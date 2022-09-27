const board = @import("board").Addresses.InterruptController;

pub fn initIc() void {
    // enabling all irq types
    // enalbles system timer
    // @intToPtr(*u32, board.Addresses.enableIrq1).* = 1 << 1;
    // @intToPtr(*u32, board.Addresses.enableIrq2).* = 1 << 1;
    // @intToPtr(*u32, board.Addresses.enableIrqBasic).* = 1 << 1;

    asm volatile ("msr daifclr, #3");
}
