const std = @import("std");
const board = @import("board");
const arm = @import("arm");
const cpuContext = arm.cpuContext;

const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr1).kprint;


const sharedKernelServices = @import("sharedKernelServices");
const Scheduler = sharedKernelServices.Scheduler;

pub fn bcm2835IrqHandlerSetup(scheduler: *Scheduler) void {
    _ = scheduler;
    board.driver.secondaryInterruptConrtollerDriver.addIcHandler(&irqHandler) catch |e| {
        kprint("[error] addIcHandler error: {s} \n", .{@errorName(e)});
        while(true) {}
    };
    kprint("inited raspberry secondary Ic \n", .{});
}

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
// bcm2835 interrupt controller handler for raspberry
const Bank0 = RegValues.Bank0;
const Bank1 = RegValues.Bank1;
const Bank2 = RegValues.Bank2;
pub fn irqHandler(context: *cpuContext.CpuContext) void {
    var irq_bank_0 = std.meta.intToEnum(Bank0, board.SecondaryInterruptControllerKpiType.RegMap.pendingBasic.*) catch |e| {
        kprint("[panic] std meta intToEnum error: {s} \n", .{@errorName(e)});
        while(true) {}
    };
    var irq_bank_1 = std.meta.intToEnum(Bank1, board.SecondaryInterruptControllerKpiType.RegMap.pendingIrq1.*) catch |e| {
        kprint("[panic] std meta intToEnum error: {s} \n", .{@errorName(e)});
        while(true) {}
    };
    var irq_bank_2 = std.meta.intToEnum(Bank2, board.SecondaryInterruptControllerKpiType.RegMap.pendingIrq2.*) catch |e| {
        kprint("[panic] std meta intToEnum error: {s} \n", .{@errorName(e)});
        while(true) {}
    };

    switch (irq_bank_0) {
        // One or more bits set in pending register 1
        Bank0.pending1 => {
            switch (irq_bank_1) {
                Bank1.timer1 => {
                        board.driver.timerDriver.timerTick(context) catch |e| {
                            kprint("[panic] timerDriver timerTick error: {s} \n", .{@errorName(e)});
                            while(true){}
                        };
                    },
                else => {
                    // kprint("Not supported 1 irq num: {s} \n", .{@tagName(irq_bank_1)});
                },
            }
        },
        // One or more bits set in pending register 2
        Bank0.pending2 => {
            switch (irq_bank_2) {
                else => {
                    // kprint("Not supported bank 2 irq num: {s} \n", .{@tagName(irq_bank_0)});
                },
            }
        },
        Bank0.armTimer => {
            board.driver.timerDriver.timerTick(context) catch |e| {
                kprint("[panic] timerDriver timerTick error: {s} \n", .{@errorName(e)});
                while(true){}
            };
        },
        else => {
            // kprint("Not supported bank(neither 1/2) irq num: {d} \n", .{intController.RegMap.pendingBasic.*});
            // raspberries timers are a mess and I'm currently unsure if the Arm Generic timer
            // has an enum defined in the banks or if it's not defined through the bcm28835 system.
            board.driver.timerDriver.timerTick(context) catch |e| {
                kprint("[panic] timerDriver timerTick error: {s} \n", .{@errorName(e)});
                while(true){}            };
        },
    }
}