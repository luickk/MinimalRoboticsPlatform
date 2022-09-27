const regs = @import("gicv2Regs.zig");
const GiccRegMap = regs.GiccRegMap;
const GicdRegMap = regs.GicdRegMap;

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

// initialize gic irq controller
pub fn gicv2Initialize() void {
    Gicc.init();
    Gicd.init();
}

pub const Gicc = struct {
    // initialize gic controller
    fn init() void {
        // disable cpu interface
        GiccRegMap.ctlr.* = regs.gicc_ctlr_disable;

        // set the priority level as the lowest priority
        // note: higher priority corresponds to a lower priority field value in the gic_pmr.
        // in addition to this, writing 255 to the gicc_pmr always sets it to the largest supported priority field value.
        GiccRegMap.pmr.* = regs.gicc_pmr_prio_min;

        // handle all of interrupts in a single group
        GiccRegMap.bpr.* = regs.gicc_bpr_no_group;

        // clear all of the active interrupts
        var pending_irq: u32 = 0;
        while (pending_irq != regs.gicc_iar_spurious_intr) : (pending_irq = GiccRegMap.iar.* & regs.gicc_iar_spurious_intr) {
            // pending_irq = ( *reg_gic_gicc_iar & gicc_iar_intr_idmask ) )
            GiccRegMap.eoir.* = GiccRegMap.eoir.*;
        }

        // enable cpu interface
        GiccRegMap.ctlr.* = regs.gicc_ctlr_enable;
    }

    // send end of interrupt to irq line for gic
    // ctrlr   irq controller information
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
        while (regs.gic_int_max > i) : (i += 1) {
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
        GicdRegMap.ctlr.* = regs.gicd_ctlr_disable;

        // disable all irqs
        regs_nr = (regs.gic_int_max + regs.gicd_int_per_reg - 1) / regs.gicd_int_per_reg;
        while (regs_nr > i) : (i += 1) {
            GicdRegMap.calcReg(GicdRegMap.icenabler, i).* = ~@as(u32, 0);
        }
        i = 0;

        // clear all pending irqs
        regs_nr = (regs.gic_int_max + regs.gicd_int_per_reg - 1) / regs.gicd_int_per_reg;
        while (regs_nr > i) : (i += 1) {
            GicdRegMap.calcReg(GicdRegMap.icpendr, i).* = ~@as(u32, 0);
        }
        i = 0;

        // set all of interrupt priorities as the lowest priority
        regs_nr = (regs.gic_int_max + regs.gicd_ipriority_per_reg - 1) / regs.gicd_ipriority_per_reg;
        while (regs_nr > i) : (i += 1) {
            GicdRegMap.calcReg(GicdRegMap.ipriorityr, i).* = ~@as(u32, 0);
        }
        i = 0;

        // set target of all of shared arm to processor 0
        i = regs.gic_intno_spi0 / regs.gicd_itargetsr_per_reg;
        while ((regs.gic_int_max + (regs.gicd_itargetsr_per_reg - 1)) / regs.gicd_itargetsr_per_reg > i) : (i += 1) {
            GicdRegMap.calcReg(GicdRegMap.itargetsr, i).* = @as(u32, regs.gicd_itargetsr_core0_target_bmap);
        }

        // set trigger type for all peripheral interrupts level triggered
        i = regs.gic_intno_ppi0 / regs.gicd_icfgr_per_reg;
        while ((regs.gic_int_max + (regs.gicd_icfgr_per_reg - 1)) / regs.gicd_icfgr_per_reg > i) : (i += 1) {
            GicdRegMap.calcReg(GicdRegMap.icfgr, i).* = regs.gicd_icfgr_level;
        }

        // enable distributor
        GicdRegMap.ctlr.* = regs.gicd_ctlr_enable;
    }

    // disable irq
    // irq irq number
    pub fn gicdDisableInt(irq: u32) void {
        GicdRegMap.calcReg(GicdRegMap.icenabler, irq / regs.gicd_icenabler_per_reg).* = @as(u8, 1) << @truncate(u3, irq % regs.gicd_icenabler_per_reg);
    }

    // enable irq
    // irq irq number
    pub fn gicdEnableInt(irq: u32) void {
        GicdRegMap.calcReg(GicdRegMap.isenabler, irq / regs.gicd_isenabler_per_reg).* = @as(u8, 1) << @truncate(u3, irq % regs.gicd_isenabler_per_reg);
    }

    // clear a pending interrupt
    // irq irq number
    fn gicdClearPending(irq: u32) void {
        GicdRegMap.calcReg(GicdRegMap.icpendr, irq / regs.gicd_icpendr_per_reg).* = @as(u8, 1) << @truncate(u3, irq % regs.gicd_icpendr_per_reg);
    }

    // probe pending interrupt
    // irq irq number
    fn gicdProbePending(irq: u32) bool {
        var is_pending = (GicdRegMap.calcReg(GicdRegMap.ispendr, (irq / regs.gicd_ispendr_per_reg)).* & (@as(u8, 1) << @truncate(u3, irq % regs.gicd_ispendr_per_reg)));
        return is_pending != 0;
    }

    // set an interrupt target processor
    // irq irq number
    // p   target processor mask
    // 0x1 processor 0
    // 0x2 processor 1
    // 0x4 processor 2
    // 0x8 processor 3
    fn gicdSetTarget(irq: u32, p: u32) void {
        var shift: u5 = @truncate(u5, (irq % regs.gic_gicd_itargetsr_per_reg) * regs.gic_gicd_itargetsr_size_per_reg);

        var reg: u32 = regs.reg_gic_gicd_itargetsr(irq / regs.gic_gicd_itargetsr_per_reg).*;
        reg &= ~(@as(u32, 0xff) << shift);
        reg |= p << shift;
        regs.reg_gic_gicd_itargetsr(irq / regs.gic_gicd_itargetsr_per_reg).* = reg;
    }

    // set an interrupt priority
    // irq  irq number
    // prio interrupt priority in arm specific expression
    fn gicdSetPriority(irq: u32, prio: u32) void {
        var shift: u5 = @truncate(u5, (irq % regs.gic_gicd_ipriority_per_reg) * regs.gic_gicd_ipriority_size_per_reg);
        var reg: u32 = regs.reg_gic_gicd_ipriorityr(irq / regs.gic_gicd_ipriority_per_reg).*;
        reg &= ~(@as(u32, 0xff) << shift);
        reg |= (prio << shift);
        regs.reg_gic_gicd_ipriorityr(irq / regs.gic_gicd_ipriority_per_reg).* = reg;
    }

    // configure irq
    // irq     irq number
    // config  configuration value for gicd_icfgr
    fn gicdConfig(irq: u32, config: u32) void {
        var shift: u5 = @truncate(u5, (irq % regs.gic_gicd_icfgr_per_reg) * regs.gic_gicd_icfgr_size_per_reg); // gicd_icfgr has 17 fields, each field has 2bits.

        var reg: u32 = regs.reg_gic_gicd_icfgr(irq / regs.gic_gicd_icfgr_per_reg).*;

        reg &= ~((@as(u32, 0x03)) << shift); // clear the field
        reg |= ((@as(u32, config)) << shift); // set the value to the field correponding to irq
        regs.reg_gic_gicd_icfgr(irq / regs.gic_gicd_icfgr_per_reg).* = reg;
    }
};
