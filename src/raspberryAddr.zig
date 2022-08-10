const rpBase: usize = 0x3f000000;

pub const serialMmio = @intToPtr(*volatile u8, rpBase + 0x201000);

pub const Timer = struct {
    pub const timerClo: usize = rpBase + 0x00003004;
    pub const timerC1: usize = rpBase + 0x00003010;
    pub const timerCs: usize = rpBase + 0x00003000;

    // address values
    pub const Values = struct {
        pub const timerInterval: u32 = 200000;
        pub const timerCsM0: u32 = 1 << 0;
        pub const timerCsM1: u32 = 1 << 1;
        pub const timerCsM2: u32 = 1 << 2;
        pub const timerCsM3: u32 = 1 << 3;
    };
};

pub const InterruptController = struct {
    // addresses
    pub const pendingBasic: usize = rpBase + 0x0000b200;
    pub const pendingIrq1: usize = rpBase + 0x0000b204;
    pub const pendingIrq2: usize = rpBase + 0x0000b208;

    pub const enableIrq1: usize = rpBase + 0x0000b210;
    pub const enableIrq2: usize = rpBase + 0x0000b214;
    pub const enableIrqBasic: usize = rpBase + 0x0000b218;

    // address values
    pub const Values = struct {

        // all banks are lister here: https://github.com/torvalds/linux/blob/master/Documentation/devicetree/bindings/interrupt-controller/brcm%2Cbcm2835-armctrl-ic.txt
        pub const Bank0 = enum(u32) {
            armTimer = 0,
            armMailbox = 1 << 0,
            armDoorbell0 = 1 << 1,
            armDoorbell1 = 1 << 2,
            vpu0Halted = 1 << 3,
            vpu1Halted = 1 << 4,
            illegalType0 = 1 << 5,
            illegalType1 = 1 << 6,
            pending1 = 1 << 7,
            pending2 = 1 << 8,
        };

        pub const Bank1 = enum(u32) {
            timer0 = 0,
            timer1 = 1 << 0,
            timer2 = 1 << 1,
            timer3 = 1 << 2,
            codec0 = 1 << 3,
            codec1 = 1 << 4,
            codec2 = 1 << 5,
            vcJpeg = 1 << 6,
            isp = 1 << 7,
            vcUsb = 1 << 8,
            vc3d = 1 << 9,
            transposer = 1 << 10,
            multicoresync0 = 1 << 11,
            multicoresync1 = 1 << 12,
            multicoresync2 = 1 << 13,
            multicoresync3 = 1 << 14,
            dma0 = 1 << 15,
            dma1 = 1 << 16,
            vcDma2 = 1 << 17,
            vcDma3 = 1 << 18,
            dma4 = 1 << 19,
            dma5 = 1 << 20,
            dma6 = 1 << 21,
            dma7 = 1 << 22,
            dma8 = 1 << 23,
            dma9 = 1 << 24,
            dma10 = 1 << 25,
            // 27: dma11-14 - shared interrupt for dma 11 to 14
            dma11 = 1 << 26,
            // 28: dmaall - triggers on all dma interrupts (including chanel 15)
            dmaall = 1 << 27,
            aux = 1 << 28,
            arm = 1 << 29,
            vpudma = 1 << 30,
        };

        // bank2
        pub const Bank2 = enum(u32) {
            hostport = 0,
            videoscaler = 1 << 0,
            ccp2tx = 1 << 1,
            sdc = 1 << 2,
            dsi0 = 1 << 3,
            ave = 1 << 4,
            cam0 = 1 << 5,
            cam1 = 1 << 6,
            hdmi0 = 1 << 7,
            hdmi1 = 1 << 8,
            pixelValve1 = 1 << 9,
            i2cSpislv = 1 << 10,
            dsi1 = 1 << 11,
            pwa0 = 1 << 12,
            pwa1 = 1 << 13,
            cpr = 1 << 14,
            smi = 1 << 15,
            gpio0 = 1 << 16,
            gpio1 = 1 << 17,
            gpio2 = 1 << 18,
            gpio3 = 1 << 19,
            vci2c = 1 << 20,
            vcSpi = 1 << 21,
            vcI2spcm = 1 << 22,
            vcSdio = 1 << 23,
            vcUart = 1 << 24,
            slimbus = 1 << 25,
            vec = 1 << 26,
            cpg = 1 << 27,
            rng = 1 << 28,
            vcArasansdio = 1 << 29,
            avspmon = 1 << 30,
        };
    };
};
