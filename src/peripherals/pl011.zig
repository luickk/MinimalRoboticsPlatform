const std = @import("std");
const board = @import("board");
const pl011Addr = @import("board").Addresses.Pl011;

pub const Pl011 = struct {
    const RegMap = struct {
        pub const dr = @intToPtr(*volatile u32, pl011Addr.base_address + 0x000);
        pub const fr = @intToPtr(*volatile u32, pl011Addr.base_address + 0x018);
        pub const ibrd = @intToPtr(*volatile u32, pl011Addr.base_address + 0x024);
        pub const fbrd = @intToPtr(*volatile u32, pl011Addr.base_address + 0x028);
        pub const lcr = @intToPtr(*volatile u32, pl011Addr.base_address + 0x02c);
        pub const cr = @intToPtr(*volatile u32, pl011Addr.base_address + 0x030);
        pub const imsc = @intToPtr(*volatile u32, pl011Addr.base_address + 0x038);
        pub const dmacr = @intToPtr(*volatile u32, pl011Addr.base_address + 0x048);
    };

    fn waitForTransmissionEnd() void {
        // 1 << 3 -> busy bit in fr reg
        while (RegMap.fr.* & @as(u32, 1 << 3) != 0) {}
    }
    // used for fbrd, ibrd config registers
    fn calcClockDevisor() struct { integer: u16, fraction: u6 } {
        const div: u32 = 4 * pl011Addr.base_address / pl011Addr.base_clock;
        return .{ .integer = (div >> 6) & 0xffff, .fraction = div & 0x3f };
    }

    pub fn init() void {

        // disable uart
        RegMap.cr.* = RegMap.cr.* & @as(u32, 1 << 0);

        waitForTransmissionEnd();

        // flush fifo
        RegMap.lcr.* = RegMap.lcr.* & ~@as(u32, 1 << 4);

        // calc int and fraction part of the clock devisor and write it to regs
        var dev = calcClockDevisor();
        RegMap.ibrd.* = dev.integer;
        RegMap.fbrd.* = dev.fraction;

        // // Configure data frame format according to the parameters (UARTLCR_H).
        // // We don't actually use all the possibilities, so this part of the code
        // // can be simplified.
        // var lcr: u32 = 0;
        // // WLEN part of UARTLCR_H, you can check that this calculation does the right thing for yourself
        // lcr |= ((pl011Addr.data_bits - 1) & 0x3) << 5;
        // // Configure the number of stop bits
        // if (pl011Addr.stop_bits == 2)
        //     // 2 -> 3 bit shift
        //     lcr |= (1 << 3);

        // Mask all interrupts by setting corresponding bits to 1
        RegMap.imsc.* = 0x7ff;

        // Disable DMA by setting all bits to 0
        RegMap.dmacr.* = 0x0;

        // 8 enables uart, 0 tx
        RegMap.cr.* = @as(u32, 1 << 8) | @as(u32, 1 << 0);
    }

    pub fn write(data: []const u8) void {
        waitForTransmissionEnd();
        for (data) |ch| {
            RegMap.dr.* = ch;
            waitForTransmissionEnd();
        }
    }
};
