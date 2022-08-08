use crate::serial::kprint;
use crate::utils;
use crate::ic;

// bcm2835 interrupt controller handler
#[inline(always)]
pub extern "C" fn ic_handle(exc: *const ic::ExceptionFrame) {
	let irq_bank_0 = utils::read_from::<u32>(ic::IRQ_PENDING_BASIC);
	let irq_bank_2 = utils::read_from::<u32>(ic::IRQ_PENDING_BASIC+8);
	let irq_bank_1 = utils::read_from::<u32>(ic::IRQ_PENDING_BASIC+4);

	// if interrupt is triggerd and all banks indicate 0, src is not supported(?)
	if irq_bank_0 == 0 && irq_bank_1 == 0 && irq_bank_2 == 0 {
		unsafe {
			let exc = *exc;
		    let ec = exc.esr_el1 << 32; // 6 bits in size
		    let ec = ec >> 58 as u64;
		    if let Some(ec_type) = ic::ec_from_u64(ec){
			    if ec_type != ic::ExceptionClass::UnknownReason {
					kprint!(".........INT............\n");
					kprint!("b0: {:#b} \n", irq_bank_0);
					kprint!("b1: {:#b} \n", irq_bank_1);
					kprint!("b2: {:#b} \n", irq_bank_2);

					kprint!("INT type: ");
					// ugly ugly rust. I want back to C ):
					match exc.int_type {
						0x1 => {
				    		kprint!("EL1_SYNC \n");
						},
						0x2 => {
				    		kprint!("EL1_FIQ \n");
						},
						0x3 => {
				    		kprint!("EL1_IRQ \n");
						},
						0x4 => {
				    		kprint!("EL1_ERR \n");
						},
						_ => {
				    		kprint!("other \n");	
						}
					}
				    kprint!("Ec: {:?} \n", ec_type);
				    kprint!(".........INT............\n");	
			    }
		    } else {
		    	kprint!("unknwown IRQ EC! \n");
		    	panic!();
		    }
		}
	}
	match irq_bank_0 {
		ic::ARM_TIMER => {
			// system timer
			// todo => implement kernel timer
			// kprint!("arm timer irq b0\n");
			return;
		},
		ic::ARM_MAILBOX => {
			kprint!("arm mailbox\n");
		},
		ic::ARM_DOORBELL_0 => {
			kprint!("arm doorbell\n");
		},
		ic::ARM_DOORBELL_1 => {
			kprint!("armm doorbell 1 b1\n");
		},
		ic::VPU0_HALTED => {},
		ic::VPU1_HALTED => {},
		ic::ILLEGAL_TYPE0 => {},
		ic::ILLEGAL_TYPE1 => {},
		// One or more bits set in pending register 1
		ic::PENDING_1 => {
			match irq_bank_1 {
				// todo => implement timer
				ic::TIMER0 => {},
				ic::TIMER1 => {},
				ic::TIMER2 => {},
				ic::TIMER3 => {},
				_ => {
					kprint!("Unknown IC bank 1 irq num: {:#b} \n", irq_bank_1);
				}		
			}
			
		},
		// One or more bits set in pending register 2
		ic::PENDING_2 => {
			match irq_bank_2 {
				_ => {
					kprint!("Unknown IC bank 2 irq num: {:#b} \n", irq_bank_2);
				}	
			}
		},
		_ => {
			kprint!("Unknown IC bank 0 irq num: {:#b} \n", irq_bank_0);
		}
	}
}