const AddrSpace = @import("board").boardConfig.AddrSpace;

pub fn InterruptController(comptime addr_space: AddrSpace) type {
    const base_address = @import("board").PeriphConfig(addr_space).InterruptController.base_address;
    return struct {
        const Self = @This();

        pub const RegMap = struct {
            pub const pendingBasic = @intToPtr(*volatile u32, base_address + 0);
            pub const pendingIrq1 = @intToPtr(*volatile u32, base_address + 0x4);
            pub const pendingIrq2 = @intToPtr(*volatile u32, base_address + 0x8);

            pub const enableIrq1 = @intToPtr(*volatile u32, base_address + 0x10);
            pub const enableIrq2 = @intToPtr(*volatile u32, base_address + 0x14);
            pub const enableIrqBasic = @intToPtr(*volatile u32, base_address + 0x18);
        };
        pub const RegValues = struct {
            // all banks are lister here: https://github.com/torvalds/linux/blob/master/Documentation/devicetree/bindings/interrupt-controller/brcm%2Cbcm2835-armctrl-ic.txt
            pub const Bank0 = enum(u32) {
                armTimer = 1 << 0,
                armMailbox = 1 << 1,
                armDoorbell0 = 1 << 2,
                armDoorbell1 = 1 << 3,
                vpu0Halted = 1 << 4,
                vpu1Halted = 1 << 5,
                illegalType0 = 1 << 6,
                illegalType1 = 1 << 7,
                pending1 = 1 << 8,
                pending2 = 1 << 9,
                notDefined = 0,
            };

            pub const Bank1 = enum(u32) {
                timer0 = 1 << 0,
                timer1 = 1 << 1,
                timer2 = 1 << 2,
                timer3 = 1 << 3,
                codec0 = 1 << 4,
                codec1 = 1 << 5,
                codec2 = 1 << 6,
                vcJpeg = 1 << 7,
                isp = 1 << 8,
                vcUsb = 1 << 9,
                vc3d = 1 << 10,
                transposer = 1 << 11,
                multicoresync0 = 1 << 12,
                multicoresync1 = 1 << 13,
                multicoresync2 = 1 << 14,
                multicoresync3 = 1 << 15,
                dma0 = 1 << 16,
                dma1 = 1 << 17,
                vcDma2 = 1 << 18,
                vcDma3 = 1 << 19,
                dma4 = 1 << 20,
                dma5 = 1 << 21,
                dma6 = 1 << 22,
                dma7 = 1 << 23,
                dma8 = 1 << 24,
                dma9 = 1 << 25,
                dma10 = 1 << 26,
                // 27: dma11-14 - shared interrupt for dma 11 to 14
                dma11 = 1 << 27,
                // 28: dmaall - triggers on all dma interrupts (including chanel 15)
                dmaall = 1 << 28,
                aux = 1 << 29,
                arm = 1 << 30,
                vpudma = 1 << 31,
                notDefined = 0,
            };
            // bank2
            pub const Bank2 = enum(u32) {
                hostport = 1 << 0,
                videoscaler = 1 << 1,
                ccp2tx = 1 << 2,
                sdc = 1 << 3,
                dsi0 = 1 << 4,
                ave = 1 << 5,
                cam0 = 1 << 6,
                cam1 = 1 << 7,
                hdmi0 = 1 << 8,
                hdmi1 = 1 << 9,
                pixelValve1 = 1 << 10,
                i2cSpislv = 1 << 11,
                dsi1 = 1 << 12,
                pwa0 = 1 << 13,
                pwa1 = 1 << 14,
                cpr = 1 << 15,
                smi = 1 << 16,
                gpio0 = 1 << 17,
                gpio1 = 1 << 18,
                gpio2 = 1 << 19,
                gpio3 = 1 << 20,
                vci2c = 1 << 21,
                vcSpi = 1 << 22,
                vcI2spcm = 1 << 23,
                vcSdio = 1 << 24,
                vcUart = 1 << 25,
                slimbus = 1 << 26,
                vec = 1 << 27,
                cpg = 1 << 28,
                rng = 1 << 29,
                vcArasansdio = 1 << 30,
                avspmon = 1 << 31,
                notDefined = 0,
            };
        };
        const icAddr = @import("board").PeriphConfig(addr_space).InterruptController;
        pub fn init() void {
            // enabling all irq types
            // enalbles system timer
            RegMap.enableIrq1.* = 1 << 1;
            // RegMap.enableIrq2.* = 1 << 1;
            // RegMap.enableIrqBasic.* = 1 << 1;

        }
    };
}
