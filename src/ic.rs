use crate::utils;


const RP_BASE: usize = 0x3F000000;
const ENABLE_IRQ: usize = RP_BASE+0x0000B210;
pub const IRQ_PENDING: usize = RP_BASE+0x0000B200;
const TIMER_CLO:usize = RP_BASE+0x00003004;
const TIMER_C1:usize = RP_BASE+0x00003010;
pub const ARM_TIMER_IRQ: u32 = 0 ^ (1 << 1);
pub const ONE_OR_MORE_SET_IN_PENDING: u32 = 0 ^ (1 << 8);
const TIMER_INTERVAL: u32 = 200000;

// reads interrupt data placed by exc. vec from the stack
#[repr(C)] 
#[derive(Clone, Copy)]
pub struct ExceptionFrame {
    pub regs: [u64; 30],
    pub elr_el1: u64,
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
	utils::write_to(ENABLE_IRQ, ARM_TIMER_IRQ);
	// configure irq mask
	unsafe {
		core::arch::asm!("msr daifclr, #0");
	}

}
