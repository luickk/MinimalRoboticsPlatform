#![allow(dead_code)]
#![allow(unused_variables)]

use crate::utils;

const RP_BASE: usize = 0x3F000000;
pub const IRQ_PENDING_BASIC: usize = RP_BASE+0x0000B200;
const ENABLE_IRQ_1: usize = RP_BASE+0x0000B210;
const ENABLE_IRQ_2: usize = RP_BASE+0x0000B214;
const ENABLE_IRQ_BASIC: usize = RP_BASE+0x0000B218;

const TIMER_CLO:usize = RP_BASE+0x00003004;
const TIMER_C1:usize = RP_BASE+0x00003010;
const TIMER_INTERVAL: u32 = 200000;

// identifiers for the vector table ic_handler call
#[no_mangle]
pub static EL1_SYNC: u64 = 0x1;
#[no_mangle]
pub static EL1_IRQ: u64 = 0x2;
#[no_mangle]
pub static EL1_FIQ: u64 = 0x3;
#[no_mangle]
pub static EL1_ERR: u64 = 0x4;
#[no_mangle]
pub static ELX_SPX: u64 = 0x5;


// BANK0
pub const ARM_TIMER: u32 = 0;
pub const ARM_MAILBOX: u32 = 1 << 0;
pub const ARM_DOORBELL_0: u32 = 1 << 1;
pub const ARM_DOORBELL_1: u32 = 1 << 2;
pub const VPU0_HALTED: u32 = 1 << 3;
pub const VPU1_HALTED: u32 = 1 << 4;
pub const ILLEGAL_TYPE0: u32 = 1 << 5;
pub const ILLEGAL_TYPE1: u32 = 1 << 6;
pub const PENDING_1: u32 = 1 << 7;
pub const PENDING_2: u32 = 1 << 8;


// BANK1
pub const TIMER0: u32 = 0;
pub const TIMER1: u32 = 1 << 0;
pub const TIMER2: u32 = 1 << 1;
pub const TIMER3: u32 = 1 << 2;
pub const CODEC0: u32 = 1 << 3;
pub const CODEC1: u32 = 1 << 4;
pub const CODEC2: u32 = 1 << 5;
pub const VC_JPEG: u32 = 1 << 6;
pub const ISP: u32 = 1 << 7;
pub const VC_USB: u32 = 1 << 8;
pub const VC_3D: u32 = 1 << 9;
pub const TRANSPOSER: u32 = 1 << 10;
pub const MULTICORESYNC0: u32 = 1 << 11;
pub const MULTICORESYNC1: u32 = 1 << 12;
pub const MULTICORESYNC2: u32 = 1 << 13;
pub const MULTICORESYNC3: u32 = 1 << 14;
pub const DMA0: u32 = 1 << 15;
pub const DMA1: u32 = 1 << 16;
pub const VC_DMA2: u32 = 1 << 17;
pub const VC_DMA3: u32 = 1 << 18;
pub const DMA4: u32 = 1 << 19;
pub const DMA5: u32 = 1 << 20;
pub const DMA6: u32 = 1 << 21;
pub const DMA7: u32 = 1 << 22;
pub const DMA8: u32 = 1 << 23;
pub const DMA9: u32 = 1 << 24;
pub const DMA10: u32 = 1 << 25;
// 27: DMA11-14 - shared interrupt for DMA 11 to 14
pub const DMA11: u32 = 1 << 26;
// 28: DMAALL - triggers on all dma interrupts (including chanel 15)
pub const DMAALL: u32 = 1 << 27;
pub const AUX: u32 = 1 << 28;
pub const ARM: u32 = 1 << 29;
pub const VPUDMA: u32 = 1 << 30;

// BANK2
pub const HOSTPORT: u32 = 0;
pub const VIDEOSCALER: u32 = 1 << 0;
pub const CCP2TX: u32 = 1 << 1;
pub const SDC: u32 = 1 << 2;
pub const DSI0: u32 = 1 << 3;
pub const AVE: u32 = 1 << 4;
pub const CAM0: u32 = 1 << 5;
pub const CAM1: u32 = 1 << 6;
pub const HDMI0: u32 = 1 << 7;
pub const HDMI1: u32 = 1 << 8;
pub const PIXELVALVE1: u32 = 1 << 9;
pub const I2CSPISLV: u32 = 1 << 10;
pub const DSI1: u32 = 1 << 11;
pub const PWA0: u32 = 1 << 12;
pub const PWA1: u32 = 1 << 13;
pub const CPR: u32 = 1 << 14;
pub const SMI: u32 = 1 << 15;
pub const GPIO0: u32 = 1 << 16;
pub const GPIO1: u32 = 1 << 17;
pub const GPIO2: u32 = 1 << 18;
pub const GPIO3: u32 = 1 << 29;
pub const VC_I2C: u32 = 1 << 20;
pub const VC_SPI: u32 = 1 << 21;
pub const VC_I2SPCM: u32 = 1 << 22;
pub const VC_SDIO: u32 = 1 << 23;
pub const VC_UART: u32 = 1 << 24;
pub const SLIMBUS: u32 = 1 << 25;
pub const VEC: u32 = 1 << 26;
pub const CPG: u32 = 1 << 27;
pub const RNG: u32 = 1 << 28;
pub const VC_ARASANSDIO: u32 = 1 << 29;
pub const AVSPMON: u32 = 1 << 30;

// reads interrupt data placed by exc. vec from the stack
#[repr(C)] 
#[derive(Clone, Copy)]
pub struct ExceptionFrame {
    pub regs: [u64; 30],
    pub int_type: u64,
    pub esr_el1: u64,
    pub spsr_el1: u64,
    pub lr: u64,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum ExceptionClass {
    UnknownReason = 0b000000,
    TrappedWF = 0b000001,
    TrappedMCR = 0b000011,
    TrappedMcrr = 0b000100,
    TrappedMCRWithAcc = 0b000101,
    TrappedLdcStcAcc = 0b000110,
    SveAsmidFpAcc = 0b000111,
    TrappedLdStInst = 0b001010,
    TrappedMrrcWithAcc = 0b001100,
    BranchTargetExc = 0b001101,
    IllegalExecState = 0b001110,
    SvcInstExcAArch32 = 0b010001,
    SvcInstExAArch64 = 0b010101,
    TrappedMsrMrsSiAarch64 = 0b011000,
    SveFuncTrappedAcc = 0b011001,
    SxcFromPointerAuthInst = 0b011100,
    InstAbortFromLowerExcLvl = 0b100000,
    InstAbortTakenWithoutExcLvlChange = 0b100001,
    PcAlignFaultExc = 0b100010,
    DataAbortFromLowerExcLvl = 0b100100,
    DataAbortWithoutExcLvlChange = 0b100101,
    SpAlignmentFaultExc = 0b100110,
    TrappedFpExcAarch32 = 0b101000,
    TrappedFpExcAarch64 = 0b101100,
    BrkPExcFromLowerExcLvl = 0b101111,
    BrkPExcWithoutExcLvlChg = 0b110001,
    SoftwStepExcpFromLowerExcLvl = 0b110010,
    SoftwStepExcTakenWithoutExcLvlChange = 0b110011,
    WatchPointExcpFromALowerExcLvl = 0b110100,
    WatchPointExcpWithoutTakenWithoutExcLvlChange = 0b110101,
    BkptInstExecAarch32 = 0b111000,
    BkptInstExecAarch64 = 0b111100,
}

// extremely ugly int mapping(rust without std..)
pub fn ec_from_u64(ec: u64) -> Option<ExceptionClass> {
	match ec {
	    ec if ec == ExceptionClass::UnknownReason as u64 => Some(ExceptionClass::UnknownReason),
	    ec if ec == ExceptionClass::TrappedWF as u64 => Some(ExceptionClass::TrappedWF),
	    ec if ec == ExceptionClass::TrappedMCR as u64 => Some(ExceptionClass::TrappedMCR),
	    ec if ec == ExceptionClass::TrappedMcrr as u64 => Some(ExceptionClass::TrappedMcrr),
	    ec if ec == ExceptionClass::TrappedMCRWithAcc as u64 => Some(ExceptionClass::TrappedMCRWithAcc),
	    ec if ec == ExceptionClass::TrappedLdcStcAcc as u64 => Some(ExceptionClass::TrappedLdcStcAcc),
	    ec if ec == ExceptionClass::SveAsmidFpAcc as u64 => Some(ExceptionClass::SveAsmidFpAcc),
	    ec if ec == ExceptionClass::TrappedLdStInst as u64 => Some(ExceptionClass::TrappedLdStInst),
	    ec if ec == ExceptionClass::TrappedMrrcWithAcc as u64 => Some(ExceptionClass::TrappedMrrcWithAcc),
	    ec if ec == ExceptionClass::BranchTargetExc as u64 => Some(ExceptionClass::BranchTargetExc),
	    ec if ec == ExceptionClass::IllegalExecState as u64 => Some(ExceptionClass::IllegalExecState),
	    ec if ec == ExceptionClass::SvcInstExcAArch32 as u64 => Some(ExceptionClass::SvcInstExcAArch32),
	    ec if ec == ExceptionClass::SvcInstExAArch64 as u64 => Some(ExceptionClass::SvcInstExAArch64),
	    ec if ec == ExceptionClass::TrappedMsrMrsSiAarch64 as u64 => Some(ExceptionClass::TrappedMsrMrsSiAarch64),
	    ec if ec == ExceptionClass::SveFuncTrappedAcc as u64 => Some(ExceptionClass::SveFuncTrappedAcc),
	    ec if ec == ExceptionClass::SxcFromPointerAuthInst as u64 => Some(ExceptionClass::SxcFromPointerAuthInst),
	    ec if ec == ExceptionClass::InstAbortFromLowerExcLvl as u64 => Some(ExceptionClass::InstAbortFromLowerExcLvl),
	    ec if ec == ExceptionClass::InstAbortTakenWithoutExcLvlChange as u64 => Some(ExceptionClass::InstAbortTakenWithoutExcLvlChange),
	    ec if ec == ExceptionClass::PcAlignFaultExc as u64 => Some(ExceptionClass::PcAlignFaultExc),
	    ec if ec == ExceptionClass::DataAbortFromLowerExcLvl as u64 => Some(ExceptionClass::DataAbortFromLowerExcLvl),
	    ec if ec == ExceptionClass::DataAbortWithoutExcLvlChange as u64 => Some(ExceptionClass::DataAbortWithoutExcLvlChange),
	    ec if ec == ExceptionClass::SpAlignmentFaultExc as u64 => Some(ExceptionClass::SpAlignmentFaultExc),
	    ec if ec == ExceptionClass::TrappedFpExcAarch32 as u64 => Some(ExceptionClass::TrappedFpExcAarch32),
	    ec if ec == ExceptionClass::TrappedFpExcAarch64 as u64 => Some(ExceptionClass::TrappedFpExcAarch64),
	    ec if ec == ExceptionClass::BrkPExcFromLowerExcLvl as u64 => Some(ExceptionClass::BrkPExcFromLowerExcLvl),
	    ec if ec == ExceptionClass::BrkPExcWithoutExcLvlChg as u64 => Some(ExceptionClass::BrkPExcWithoutExcLvlChg),
	    ec if ec == ExceptionClass::SoftwStepExcpFromLowerExcLvl as u64 => Some(ExceptionClass::SoftwStepExcpFromLowerExcLvl),
	    ec if ec == ExceptionClass::SoftwStepExcTakenWithoutExcLvlChange as u64 => Some(ExceptionClass::SoftwStepExcTakenWithoutExcLvlChange),
	    ec if ec == ExceptionClass::WatchPointExcpFromALowerExcLvl as u64 => Some(ExceptionClass::WatchPointExcpFromALowerExcLvl),
	    ec if ec == ExceptionClass::WatchPointExcpWithoutTakenWithoutExcLvlChange as u64 => Some(ExceptionClass::WatchPointExcpWithoutTakenWithoutExcLvlChange),
	    ec if ec == ExceptionClass::BkptInstExecAarch32 as u64 => Some(ExceptionClass::BkptInstExecAarch32),
	    ec if ec == ExceptionClass::BkptInstExecAarch64 as u64 => Some(ExceptionClass::BkptInstExecAarch64),
	    _ => None
	}
}	

pub fn timer_init () {
	let mut cur_val: u32 = utils::read_from(TIMER_CLO);
	cur_val += TIMER_INTERVAL;
	utils::write_to(TIMER_C1, cur_val);
}

pub fn init_ic() {
	// enabling all irq types 
	utils::write_to(ENABLE_IRQ_1, 1 as u32);
	utils::write_to(ENABLE_IRQ_2, 1 as u32);
	utils::write_to(ENABLE_IRQ_BASIC, 1 as u32);
	// configure irq mask
	unsafe {
		core::arch::asm!("msr daifclr, #0");
	}

}
