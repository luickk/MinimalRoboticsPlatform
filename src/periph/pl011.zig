const std = @import("std");
const board = @import("board");
const AddrSpace = board.boardConfig.AddrSpace;

pub fn Pl011(comptime addr_space: AddrSpace) type {
    const pl011Cfg = board.PeriphConfig(addr_space).Pl011;
    return struct {
        const RegMap = struct {
            pub const dataReg = @intToPtr(*volatile u32, pl011Cfg.base_address + 0x000);
            pub const flagReg = @intToPtr(*volatile u32, pl011Cfg.base_address + 0x018);
            pub const intBaudRateReg = @intToPtr(*volatile u32, pl011Cfg.base_address + 0x024);
            pub const fracBaudRateReg = @intToPtr(*volatile u32, pl011Cfg.base_address + 0x028);
            pub const lineCtrlReg = struct {
                pub const reg = @intToPtr(*volatile u32, pl011Cfg.base_address + 0x02c);
                pub const RegAttr = packed struct {
                    padding: u24 = 0,
                    stick_parity_select: bool = false,
                    tx_word_len: u2 = 3, // 3 => b11 => 8 bits
                    enable_fifo: bool = false,
                    two_stop_bits_select: bool = false,
                    even_parity_select: bool = false,
                    parity_enabled: bool = false,
                    send_break: bool = false,

                    pub fn asInt(self: RegAttr) u32 {
                        return @bitCast(u32, self);
                    }
                };
            };
            pub const ctrlReg = struct {
                pub const reg = @intToPtr(*volatile u32, pl011Cfg.base_address + 0x030);
                pub const RegAttr = packed struct {
                    padding: u16 = 0,
                    cts_hwflow_ctrl_en: bool = false,
                    rts_hwflow_ctrl_en: bool = false,
                    out2: bool = false,
                    ou1: bool = false,
                    req_to_send: bool = false,
                    data_tx_ready: bool = false,
                    rec_enable: bool = false,
                    tx_enable: bool = false,
                    loopback_enable: bool = false,
                    reserved: u4 = 0,
                    sir_low_power_irda_mode: bool = false,
                    sir_enable: bool = false,
                    uart_enable: bool = false,

                    pub fn asInt(self: RegAttr) u32 {
                        return @bitCast(u32, self);
                    }
                };
            };
            pub const intMaskSetClearReg = @intToPtr(*volatile u32, pl011Cfg.base_address + 0x038);
            pub const dmaCtrlReg = @intToPtr(*volatile u32, pl011Cfg.base_address + 0x048);
        };

        fn waitForTransmissionEnd() void {
            // 1 << 3 -> busy bit in flagReg reg
            while (RegMap.flagReg.* & @as(u32, 1 << 3) != 0) {}
        }
        // used for fracBaudRateReg, intBaudRateReg config registers
        fn calcClockDevisor() struct { integer: u16, fraction: u6 } {
            const div: u32 = 4 * pl011Cfg.base_clock / pl011Cfg.baudrate;
            return .{ .integer = (div >> 6) & 0xffff, .fraction = div & 0x3f };
        }

        pub fn init() void {
            // disable uart
            RegMap.ctrlReg.reg.* = (RegMap.ctrlReg.RegAttr{ .uart_enable = false }).asInt();

            waitForTransmissionEnd();

            // flush fifo
            RegMap.lineCtrlReg.reg.* = RegMap.lineCtrlReg.reg.* & ~@as(u32, 1 << 4);

            // calc int and fraction part of the clock devisor and write it to regs
            var dev = calcClockDevisor();
            RegMap.intBaudRateReg.* = dev.integer;
            RegMap.fracBaudRateReg.* = dev.fraction;

            var two_stop_bits = false;
            if (pl011Cfg.stop_bits == 2)
                two_stop_bits = true;
            if (pl011Cfg.data_bits != 8)
                @compileError("pl011 only supports 8 bit wlen");

            RegMap.lineCtrlReg.reg.* = (RegMap.lineCtrlReg.RegAttr{
                .two_stop_bits_select = two_stop_bits,
                .tx_word_len = 3,
                .enable_fifo = false,
            }).asInt();

            // Mask all interrupts by setting corresponding bits to 1
            RegMap.intMaskSetClearReg.* = 0x7ff;

            // Disable DMA by setting all bits to 0
            RegMap.dmaCtrlReg.* = 0;

            // enabling only tx (has to happen first according to docs)
            RegMap.ctrlReg.reg.* = (RegMap.ctrlReg.RegAttr{ .tx_enable = true }).asInt();
            RegMap.ctrlReg.reg.* = (RegMap.ctrlReg.RegAttr{ .tx_enable = true, .uart_enable = true }).asInt();
        }

        pub fn write(data: []const u8) void {
            waitForTransmissionEnd();
            for (data) |ch| {
                RegMap.dataReg.* = ch;
                waitForTransmissionEnd();
            }
        }
    };
}
