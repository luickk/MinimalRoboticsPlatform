// https://github.com/ARM-software/arm-trusted-firmware/blob/master/drivers/arm/gic/v2/gicv2_main.c

// can be read from CBAR register (https://developer.arm.com/documentation/ddi0500/e/system-control/aarch32-register-descriptions/configuration-base-address-register)
// genereal gic regs
const GIC_BASE: usize = 0x08000000;
const GICD_PIDR2_GICV3: usize =	0xffe8;

const GIC_PRI_MASK: u32 = 0xff;
const MIN_SPI_ID: u32 = 32;
const PIDR2_ARCH_REV_SHIFT: u8 = 4;
const PIDR2_ARCH_REV_MASK: u32 = 0xf;
const ARCH_REV_GICV2: u32 = 0x2;
const ARCH_REV_GICV1: u32 = 0x1;

// gic general reg vals
const FIQ_EN_BIT: u32 = 3;
const FIQ_BYP_DIS_GRP0: u32 = 5;
const CTLR_ENABLE_G0_BIT: u32 = 0;
const IRQ_BYP_DIS_GRP0: u32 = 6;
const FIQ_BYP_DIS_GRP1: u32 = 7;
const IRQ_BYP_DIS_GRP1: u32 = 8;
const CTLR_ENABLE_G1_BIT: u32 = 1;
const TYPER_IT_LINES_NO_MASK: u32 = 0x1f;
const GIC_HIGHEST_NS_PRIORITY: u32 = 0x80;

// gicc regs
const GICC_BASE: usize = GIC_BASE + 0x10000;
const GICC_CTLR: usize = 0x0;
const GICC_PMR: usize = 0x4;
const GICC_CTLR_DISABLE: u32 = 0x0;
const GICC_BPR: usize = 0x8;
const GICC_BPR_NO_GROUP: u32 = 0x0;

// gicd regs
const GICD_BASE: usize = GIC_BASE;
const GICD_CTLR: usize = 0x0;
const GICD_TYPER: usize = 0x4;
const GICD_IGROUPR: u32 = 0x80;
const GICD_IGROUPR_SHIFT: u8 = 5;
const GICD_IPRIORITYR: u32 = 0x400;
const GICD_IPRIORITYR_SHIFT:u8 = 2;
const GICD_ICFGR: u32 = 0xc00;
const GICD_ICFGR_SHIFT: u8 = 4;

/* Value used to initialize Normal world interrupt priorities four at a time */
const GICD_IPRIORITYR_DEF_VAL: u32 = GIC_HIGHEST_NS_PRIORITY	| (GIC_HIGHEST_NS_PRIORITY << 8)	| (GIC_HIGHEST_NS_PRIORITY << 16)	| (GIC_HIGHEST_NS_PRIORITY << 24);

// reads interrupt data placed by exc. vec from the stack
#[repr(C)]
pub struct ExceptionFrame {
    pub regs: [u64; 30],
    pub elr_el1: u64,
    pub esr_el1: u64,
    pub spsr_el1: u64,
    pub lr: u64,
}

fn read_from_gic_base<T: Copy>(base: usize, offset: usize) -> T {
	unsafe {
		let addr = (base+offset)as *mut T;
		return addr.read_volatile();	
	}
}

fn write_from_gic_base<T>(base: usize, offset: usize, val: T) {
	unsafe {
		let addr = (base+offset)as *mut T;
		addr.write_volatile(val);
	}
}

fn init_gic_gicc() {
	write_from_gic_base(GICC_BASE, GICC_CTLR, GICC_CTLR_DISABLE);

	write_from_gic_base(GICC_BASE, GICC_BPR, GICC_BPR_NO_GROUP);
	let mut val: u32;
	/*
	 * Enable the Group 0 interrupts, FIQEn and disable Group 0/1
	 * bypass.
	 */
	val = CTLR_ENABLE_G0_BIT | FIQ_EN_BIT | FIQ_BYP_DIS_GRP0;
	val |= IRQ_BYP_DIS_GRP0 | FIQ_BYP_DIS_GRP1 | IRQ_BYP_DIS_GRP1;

	/* Program the idle priority in the PMR */
	write_from_gic_base(GICC_BASE, GICC_PMR, GIC_PRI_MASK);
	write_from_gic_base(GICC_BASE, GICC_CTLR, val);
}

fn init_gic_gicd() {
	/* Disable the distributor before going further */
	let ctlr: u32 = read_from_gic_base(GICD_BASE, GICD_CTLR);
	write_from_gic_base(GICD_BASE, GICD_CTLR, ctlr & !(CTLR_ENABLE_G0_BIT | CTLR_ENABLE_G1_BIT) as u32);

	gicv2_spis_configure_defaults();

	write_from_gic_base(GICD_BASE, GICD_CTLR, ctlr | CTLR_ENABLE_G0_BIT);
}

pub fn check_gicv2_avail() -> bool {
	let mut gic_version: u32 = read_from_gic_base(GICD_BASE, GICD_PIDR2_GICV3);
	gic_version = (gic_version >> PIDR2_ARCH_REV_SHIFT) & PIDR2_ARCH_REV_MASK;

	/*
	 * GICv1 with security extension complies with trusted firmware
	 * GICv2 driver as far as virtualization and few tricky power
	 * features are not used. GICv2 features that are not supported
	 * by GICv1 with Security Extensions are:
	 * - virtual interrupt support.
	 * - wake up events.
	 * - writeable GIC state register (for power sequences)
	 * - interrupt priority drop.
	 * - interrupt signal bypass.
	 */
	if gic_version == ARCH_REV_GICV2 || gic_version == ARCH_REV_GICV1 {
		return true;
	}
	false
}

pub fn init_gic() {
	init_gic_gicc();
	init_gic_gicd();
}

// Helper function to configure the default attributes of SPIs
fn gicv2_spis_configure_defaults() {
	let mut num_ints: u32 = read_from_gic_base(GICD_BASE, GICD_TYPER);
	num_ints &= TYPER_IT_LINES_NO_MASK;
	num_ints = (num_ints + 1) << 5;

	/*
	 * Treat all SPIs as G1NS by default. The number of interrupts is
	 * calculated as 32 * (IT_LINES + 1). We do 32 at a time.
	 */
	let mut index = MIN_SPI_ID;
	let mut n: u32;
	let mut reg: u32;
	while index < num_ints {
		n = index >> GICD_IGROUPR_SHIFT;
		reg = GICD_IGROUPR + (n << 2); 
		write_from_gic_base(GICD_BASE, reg as usize, !0 as u32);
		index += 32;
	}

	/* Setup the default SPI priorities doing four at a time */
	index = MIN_SPI_ID;
	while index < num_ints {
		n = index >> GICD_IPRIORITYR_SHIFT;
		reg = GICD_IPRIORITYR + (n << 2);
		write_from_gic_base(GICD_BASE, reg as usize, GICD_IPRIORITYR_DEF_VAL as u32);
		index += 4;
	}

	/* Treat all SPIs as level triggered by default, 16 at a time */
	index = MIN_SPI_ID;
	while index < num_ints {
		n = index >> GICD_ICFGR_SHIFT;
		reg = GICD_ICFGR + (n << 2);
		write_from_gic_base(GICD_BASE, reg as usize, 0 as u32);
		index += 16;
	}
}
