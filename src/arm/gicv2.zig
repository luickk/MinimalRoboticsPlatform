// todo => make secure address comptime definable
const gicAddr = @import("board").PeriphConfig(false).GicV2;

// identifiers for the vector table addr_handler call
pub const ExceptionType = enum(u64) {
    el1Sync = 0x1,
    el1Irq = 0x2,
    el1Fiq = 0x3,
    el1Err = 0x4,
    elxSpx = 0x5,
};
export const el1Sync = ExceptionType.el1Sync;
export const el1Err = ExceptionType.el1Err;
export const el1Fiq = ExceptionType.el1Fiq;
export const el1Irq = ExceptionType.el1Irq;
export const elxSpx = ExceptionType.elxSpx;

// reads interrupt data placed by exc. vec from the stack
pub const ExceptionFrame = struct {
    regs: [30]u64,
    int_type: u64,
    esr_el1: u64,
    lr: u64,
};

pub const GicdRegValues = struct {
    // gicd...
    pub const gicdItargetsrPerReg = 4;
    pub const gicdItargetsrSizePerReg = 8;
    pub const gicdIcfgrPerReg = 16;
    pub const gicdIcfgrSizePerReg = 2;
    pub const gicdIcenablerperReg = 32;
    pub const gicdIsenablerperReg = 32;
    pub const gicdIcpendrPerReg = 32;
    pub const gicdIspendrPerReg = 32;
    pub const gicdIntPerReg = 32; // 32 interrupts per reg
    pub const gicdIpriorityPerReg = 4; // 4 priority per reg
    pub const gicdIprioritySizePerReg = 8; // priority element size
    pub const gicdItargetsrCore0TargetBmap = 0x01010101; // cpu interface 0

    // 8.9.4 gicd_ctlr, distributor control register
    pub const gicdCtlrEnable = 0x1; // enable gicd
    pub const gicdCtlrDisable = 0; // disable gicd

    // 8.9.7 gicd_icfgr<n>, interrupt configuration registers
    pub const gicdIcfgrLevel = 0; // level-sensitive
    pub const gicdIcfgrEdge = 0x2; // edge-triggered
};

// 8.8 The GIC Distributor register map
pub const GicdRegMap = struct {
    pub const gicdBase = gicAddr.base_address; // gicd mmio base address

    // Enables interrupts and affinity routing
    pub const ctlr = @intToPtr(*volatile u32, gicdBase + 0x0);
    // Deactivates the corresponding interrupt. These registers are used when saving and restoring GIC state.
    pub const intType = @intToPtr(*volatile u32, gicdBase + 0x004);
    // distributor implementer identification register
    pub const iidr = @intToPtr(*volatile u32, gicdBase + 0x008);
    // Controls whether the corresponding interrupt is in Group 0 or Group 1.
    pub const igroupr = @intToPtr(*volatile u32, gicdBase + 0x080);
    // interrupt set-enable registers
    pub const isenabler = @intToPtr(*volatile u32, gicdBase + 0x100);
    // Disables forwarding of the corresponding interrupt to the CPU interfaces.
    pub const icenabler = @intToPtr(*volatile u32, gicdBase + 0x180);
    // interrupt set-pending registers
    pub const ispendr = @intToPtr(*volatile u32, gicdBase + 0x200);
    // Removes the pending state from the corresponding interrupt.
    pub const icpendr = @intToPtr(*volatile u32, gicdBase + 0x280);
    pub const isactiver = @intToPtr(*volatile u32, gicdBase + 0x300);
    // Deactivates the corresponding interrupt. These registers are used when saving and restoring GIC state.
    pub const icactiver = @intToPtr(*volatile u32, gicdBase + 0x380);
    //  interrupt priority registers
    pub const ipriorityr = @intToPtr(*volatile u32, gicdBase + 0x400);
    // interrupt processor targets registers
    pub const itargetsr = @intToPtr(*volatile u32, gicdBase + 0x800);
    // Determines whether the corresponding interrupt is edge-triggered or level-sensitive
    pub const icfgr = @intToPtr(*volatile u32, gicdBase + 0xc00);
    // software generated interrupt register
    pub const nscar = @intToPtr(*volatile u32, gicdBase + 0xe00);
    // sgi clear-pending registers
    pub const cpendsgir = @intToPtr(*volatile u32, gicdBase + 0xf10);
    // sgi set-pending registers
    pub const spendsgir = @intToPtr(*volatile u32, gicdBase + 0xf20);
    pub const sgir = @intToPtr(*volatile u32, 0xf00);

    // from the gicv2 docs: "The number of implemented GICD_ICACTIVER<n> registers is (GICD_TYPER.ITLinesNumber+1). Registers are numbered from 0"
    pub fn calcReg(offset: *volatile u32, n: usize) *volatile u32 {
        return @intToPtr(*volatile u32, gicdBase + @as(usize, @ptrToInt(offset)) + (n * 4));
    }
};

pub const GiccRegValues = struct {
    // gicc..
    // 8.13.14 gicc_pmr, cpu interface priority mask register
    pub const giccPmrPrioMin = GiccRegMap.giccBase + 0xff; // the lowest level mask
    pub const giccPmrPrioHigh = GiccRegMap.giccBase + 0x0; // the highest level mask
    // 8.13.7 gicc_ctlr, cpu interface control register
    pub const giccCtlrEnable = 0x1; // enable gicc
    pub const giccCtlrDisable = 0x0; // disable gicc
    // 8.13.6 gicc_bpr, cpu interface binary point register
    // in systems that support only one security state, when gicc_ctlr.cbpr == 0,  this register determines only group 0 interrupt preemption.
    pub const giccBprNoGroup = 0x0; // handle all interrupts
    // 8.13.11 gicc_iar, cpu interface interrupt acknowledge register
    pub const giccIarIntrIdmask = 0x3ff; // 0-9 bits means interrupt id
    pub const giccIarSpuriousIntr = 0x3ff; // 1023 means spurious interrupt
};

// 8.12 the gic cpu interface register map
pub const GiccRegMap = struct {
    pub const giccBase = gicAddr.base_address + 0x10000; // gicc mmio base address

    // cpu interface control register
    pub const ctlr = @intToPtr(*volatile u32, giccBase + 0x000);
    // interrupt priority mask register
    pub const pmr = @intToPtr(*volatile u32, giccBase + 0x004);
    // binary point register
    pub const bpr = @intToPtr(*volatile u32, giccBase + 0x008);
    // interrupt acknowledge register
    pub const iar = @intToPtr(*volatile u32, giccBase + 0x00c);
    // end of interrupt register
    pub const eoir = @intToPtr(*volatile u32, giccBase + 0x010);
    // running priority register
    pub const rpr = @intToPtr(*volatile u32, giccBase + 0x014);
    // highest pending interrupt register
    pub const hpir = @intToPtr(*volatile u32, giccBase + 0x018);
    // aliased binary point register
    pub const abpr = @intToPtr(*volatile u32, giccBase + 0x01c);
    // cpu interface identification register
    pub const iidr = @intToPtr(*volatile u32, giccBase + 0x0fc);
};

// initialize gic irq controller
pub fn gicv2Initialize() void {
    Gicc.init();
    Gicd.init();
}

pub const Gicc = struct {
    // initialize gic controller
    fn init() void {
        // disable cpu interface
        GiccRegMap.ctlr.* = GiccRegValues.giccCtlrDisable;

        // set the priority level as the lowest priority
        // note: higher priority corresponds to a lower priority field value in the gic_pmr.
        // in addition to this, writing 255 to the gicc_pmr always sets it to the largest supported priority field value.
        GiccRegMap.pmr.* = GiccRegValues.giccPmrPrioMin;

        // handle all of interrupts in a single group
        GiccRegMap.bpr.* = GiccRegValues.giccBprNoGroup;

        // clear all of the active interrupts
        var pending_irq: u32 = 0;
        while (pending_irq != GiccRegValues.giccIarSpuriousIntr) : (pending_irq = GiccRegMap.iar.* & GiccRegValues.giccIarSpuriousIntr) {
            // pending_irq = ( *reg_gic_gicc_iar & gicc_iar_intr_idmask ) )
            GiccRegMap.eoir.* = GiccRegMap.eoir.*;
        }

        // enable cpu interface
        GiccRegMap.ctlr.* = GiccRegValues.giccCtlrEnable;
    }

    // send end of interrupt to irq line for gic
    // ctrlr   irq controller Configrmation
    // irq     irq number
    pub fn gicv2Eoi(irq: u32) void {
        Gicd.gicdClearPending(irq);
    }

    // find pending irq
    // sexc  an exception frame
    // irqp an irq number to be processed
    pub fn gicv2FindPendingIrq(exception_frame: *ExceptionFrame, irqp: *u32) u32 {
        _ = exception_frame;
        var rc: u32 = undefined;
        var i: u32 = 0;
        while (gicAddr.intMax > i) : (i += 1) {
            if (Gicd.gicdProbePending(i)) {
                rc = 0;
                irqp.* = i;
                return rc;
            }
        }

        rc = 0;
        return rc;
    }
};

pub const Gicd = struct {
    // init the gic distributor
    fn init() void {
        var i: u32 = 0;
        var regs_nr: u32 = 0;

        // diable distributor
        GicdRegMap.ctlr.* = GiccRegValues.giccCtlrDisable;

        // disable all irqs
        regs_nr = (gicAddr.intMax + GicdRegValues.gicdIntPerReg - 1) / GicdRegValues.gicdIntPerReg;
        while (regs_nr > i) : (i += 1) {
            GicdRegMap.calcReg(GicdRegMap.icenabler, i).* = ~@as(u32, 0);
        }
        i = 0;

        // clear all pending irqs
        regs_nr = (gicAddr.intMax + GicdRegValues.gicdIntPerReg - 1) / GicdRegValues.gicdIntPerReg;
        while (regs_nr > i) : (i += 1) {
            GicdRegMap.calcReg(GicdRegMap.icpendr, i).* = ~@as(u32, 0);
        }
        i = 0;

        // set all of interrupt priorities as the lowest priority
        regs_nr = (gicAddr.intMax + GicdRegValues.gicdIpriorityPerReg - 1) / GicdRegValues.gicdIpriorityPerReg;
        while (regs_nr > i) : (i += 1) {
            GicdRegMap.calcReg(GicdRegMap.ipriorityr, i).* = ~@as(u32, 0);
        }
        i = 0;

        // set target of all of shared arm to processor 0
        i = gicAddr.intNoSpi0 / GicdRegValues.gicdItargetsrPerReg;
        while ((gicAddr.intMax + (GicdRegValues.gicdItargetsrPerReg - 1)) / GicdRegValues.gicdItargetsrPerReg > i) : (i += 1) {
            GicdRegMap.calcReg(GicdRegMap.itargetsr, i).* = @as(u32, GicdRegValues.gicdItargetsrCore0TargetBmap);
        }

        // set trigger type for all armeral interrupts level triggered
        i = gicAddr.intNoPpi0 / GicdRegValues.gicdIcfgrPerReg;
        while ((gicAddr.intMax + (GicdRegValues.gicdIcfgrPerReg - 1)) / GicdRegValues.gicdIcfgrPerReg > i) : (i += 1) {
            GicdRegMap.calcReg(GicdRegMap.icfgr, i).* = GicdRegValues.gicdIcfgrLevel;
        }

        // enable distributor
        GicdRegMap.ctlr.* = GicdRegValues.gicdCtlrEnable;
    }

    // disable irq
    // irq irq number
    pub fn gicdDisableInt(irq: u32) void {
        GicdRegMap.calcReg(GicdRegMap.icenabler, irq / GiccRegValues.gicdIcenablerPerReg).* = @as(u8, 1) << @truncate(u3, irq % GiccRegValues.gicdIcenablerPerReg);
    }

    // enable irq
    // irq irq number
    pub fn gicdEnableInt(irq: u32) void {
        GicdRegMap.calcReg(GicdRegMap.isenabler, irq / GiccRegValues.gicdIsenablerPerReg).* = @as(u8, 1) << @truncate(u3, irq % GiccRegValues.gicdIsenablerPerReg);
    }

    // clear a pending interrupt
    // irq irq number
    fn gicdClearPending(irq: u32) void {
        GicdRegMap.calcReg(GicdRegMap.icpendr, irq / GiccRegValues.gicdIcpendrPerReg).* = @as(u8, 1) << @truncate(u3, irq % GiccRegValues.gicdIcpendrPerReg);
    }

    // probe pending interrupt
    // irq irq number
    fn gicdProbePending(irq: u32) bool {
        var is_pending = (GicdRegMap.calcReg(GicdRegMap.ispendr, (irq / GiccRegValues.gicdIspendrPerReg)).* & (@as(u8, 1) << @truncate(u3, irq % GiccRegValues.gicdIspendrPerReg)));
        return is_pending != 0;
    }

    // // set an interrupt target processor
    // // irq irq number
    // // p   target processor mask
    // // 0x1 processor 0
    // // 0x2 processor 1
    // // 0x4 processor 2
    // // 0x8 processor 3
    // fn gicdSetTarget(irq: u32, p: u32) void {
    //     var shift: u5 = @truncate(u5, (irq % GicdRegValues.gicdItargetsrPerReg) * GicdRegValues.gicdItargetsrSizePerReg);

    //     var reg: u32 = reg_gic_gicd_itargetsr(irq / GicdRegValues.gicdItargetsrPerReg).*;
    //     reg &= ~(@as(u32, 0xff) << shift);
    //     reg |= p << shift;
    //     reg_gic_gicd_itargetsr(irq / GicdRegValues.gicdItargetsrPerReg).* = reg;
    // }

    // // set an interrupt priority
    // // irq  irq number
    // // prio interrupt priority in arm specific expression
    // fn gicdSetPriority(irq: u32, prio: u32) void {
    //     var shift: u5 = @truncate(u5, (irq % GicdRegValues.gicdIpriorityPerReg) * GicdRegValues.gicdIprioritySizePerReg);
    //     var reg: u32 = reg_gic_gicd_ipriorityr(irq / GicdRegValues.gicdIpriorityPerReg).*;
    //     reg &= ~(@as(u32, 0xff) << shift);
    //     reg |= (prio << shift);
    //     reg_gic_gicd_ipriorityr(irq / GicdRegValues.gicdIpriorityPerReg).* = reg;
    // }

    // // configure irq
    // // irq     irq number
    // // config  configuration value for gicd_icfgr
    // fn gicdConfig(irq: u32, config: u32) void {
    //     var shift: u5 = @truncate(u5, (irq % GicdRegValues.gicdIcfgrPerReg) * GicdRegValues.gicdIcfgrSizePerReg); // gicd_icfgr has 17 fields, each field has 2bits.

    //     var reg: u32 = reg_gic_gicd_icfgr(irq / GicdRegValues.gicdIcfgrPerReg).*;

    //     reg &= ~((@as(u32, 0x03)) << shift); // clear the field
    //     reg |= ((@as(u32, config)) << shift); // set the value to the field correponding to irq
    //     reg_gic_gicd_icfgr(irq / GicdRegValues.gicdIcfgrPerReg).* = reg;
    // }
};
