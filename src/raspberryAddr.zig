const rpBase: usize = 0x3f000000;

pub const mmio_uart = @intToPtr(*volatile u8, 0x3f20_1000);

pub const iC = struct {
    pub const pendingBasic: usize = rpBase + 0x0000b200;
    pub const enableIrq1: usize = rpBase + 0x0000b210;
    pub const enableIrq2: usize = rpBase + 0x0000b214;
    pub const enableIrqBasic: usize = rpBase + 0x0000b218;

    pub const timerClo: usize = rpBase + 0x00003004;
    pub const timerC1: usize = rpBase + 0x00003010;
    pub const timerInterval: u32 = 200000;

    // bank0
    pub const armTimer: u32 = 0;
    pub const armMailbox: u32 = 1 << 0;
    pub const armDoorbell_0: u32 = 1 << 1;
    pub const armDoorbell_1: u32 = 1 << 2;
    pub const vpu0Halted: u32 = 1 << 3;
    pub const vpu1Halted: u32 = 1 << 4;
    pub const illegalType0: u32 = 1 << 5;
    pub const illegalType1: u32 = 1 << 6;
    pub const pending1: u32 = 1 << 7;
    pub const pending2: u32 = 1 << 8;

    // bank1
    pub const timer0: u32 = 0;
    pub const timer1: u32 = 1 << 0;
    pub const timer2: u32 = 1 << 1;
    pub const timer3: u32 = 1 << 2;
    pub const codec0: u32 = 1 << 3;
    pub const codec1: u32 = 1 << 4;
    pub const codec2: u32 = 1 << 5;
    pub const vcJpeg: u32 = 1 << 6;
    pub const isp: u32 = 1 << 7;
    pub const vcUsb: u32 = 1 << 8;
    pub const vc3d: u32 = 1 << 9;
    pub const transposer: u32 = 1 << 10;
    pub const multicoresync0: u32 = 1 << 11;
    pub const multicoresync1: u32 = 1 << 12;
    pub const multicoresync2: u32 = 1 << 13;
    pub const multicoresync3: u32 = 1 << 14;
    pub const dma0: u32 = 1 << 15;
    pub const dma1: u32 = 1 << 16;
    pub const vcDma2: u32 = 1 << 17;
    pub const vcDma3: u32 = 1 << 18;
    pub const dma4: u32 = 1 << 19;
    pub const dma5: u32 = 1 << 20;
    pub const dma6: u32 = 1 << 21;
    pub const dma7: u32 = 1 << 22;
    pub const dma8: u32 = 1 << 23;
    pub const dma9: u32 = 1 << 24;
    pub const dma10: u32 = 1 << 25;
    // 27: dma11-14 - shared interrupt for dma 11 to 14
    pub const dma11: u32 = 1 << 26;
    // 28: dmaall - triggers on all dma interrupts (including chanel 15)
    pub const dmaall: u32 = 1 << 27;
    pub const aux: u32 = 1 << 28;
    pub const arm: u32 = 1 << 29;
    pub const vpudma: u32 = 1 << 30;

    // bank2
    pub const hostport: u32 = 0;
    pub const videoscaler: u32 = 1 << 0;
    pub const ccp2tx: u32 = 1 << 1;
    pub const sdc: u32 = 1 << 2;
    pub const dsi0: u32 = 1 << 3;
    pub const ave: u32 = 1 << 4;
    pub const cam0: u32 = 1 << 5;
    pub const cam1: u32 = 1 << 6;
    pub const hdmi0: u32 = 1 << 7;
    pub const hdmi1: u32 = 1 << 8;
    pub const pixelValve1: u32 = 1 << 9;
    pub const i2cSpislv: u32 = 1 << 10;
    pub const dsi1: u32 = 1 << 11;
    pub const pwa0: u32 = 1 << 12;
    pub const pwa1: u32 = 1 << 13;
    pub const cpr: u32 = 1 << 14;
    pub const smi: u32 = 1 << 15;
    pub const gpio0: u32 = 1 << 16;
    pub const gpio1: u32 = 1 << 17;
    pub const gpio2: u32 = 1 << 18;
    pub const gpio3: u32 = 1 << 29;
    pub const vci2c: u32 = 1 << 20;
    pub const vcSpi: u32 = 1 << 21;
    pub const vcI2spcm: u32 = 1 << 22;
    pub const vcSdio: u32 = 1 << 23;
    pub const vcUart: u32 = 1 << 24;
    pub const slimbus: u32 = 1 << 25;
    pub const vec: u32 = 1 << 26;
    pub const cpg: u32 = 1 << 27;
    pub const rng: u32 = 1 << 28;
    pub const vcArasansdio: u32 = 1 << 29;
    pub const avspmon: u32 = 1 << 30;
};
