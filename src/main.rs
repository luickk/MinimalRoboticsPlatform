#![no_main]
#![no_std]
#![feature(exclusive_range_pattern)]

mod serial;
mod utils;
mod ic;

use serial::kprint;

use crate::ic::{ec_from_u64, ExceptionClass};

core::arch::global_asm!(include_str!("asm/exc_vec.S"));
core::arch::global_asm!(include_str!("asm/adv_boot.S"));


#[no_mangle]
pub extern "C" fn kernel_main() {
	kprint!("Booting {:?} \n", "Kernel!");

	let current_el = utils::get_current_el();
	if current_el != 1 {
		kprint!("el must be 1! (it is: {:?})\n", current_el);
		return;	
	}


	ic::timer_init();
	ic::init_ic();

	utils::test_sve_exc();
	kprint!("done \n");
}

#[no_mangle]
pub extern "C" fn common_trap_handler(exc: *const ic::ExceptionFrame) {
	let irq_bank_0 = utils::read_from::<u32>(ic::IRQ_PENDING);
	let irq_bank_1 = utils::read_from::<u32>(ic::IRQ_PENDING+4);
	let irq_bank_2 = utils::read_from::<u32>(ic::IRQ_PENDING+8);

	// if all pending irq banks are 0 then it's arm native (assumption, not certain yet!.!)
	// todo => clarify
	if irq_bank_0 == 0 && irq_bank_1 == 0 && irq_bank_2 == 0 {
		unsafe {
			let exc = *exc;
		    let ec = exc.esr_el1 << 32; // 6 bits in size
		    let ec = ec >> 58 as u64;
		    if let Some(ec_type) = ec_from_u64(ec){
		    	// todo => fix flood with uknown reason
		    	if ec_type != ExceptionClass::UnknownReason {
				    kprint!("Esr: {:#b} \n", exc.esr_el1);
				    kprint!("Ec: {:#b} \n", ec);
				    kprint!("Ec: {:?} \n", ec_type);	
		    	}
		    } else {
		    	kprint!("unknwown IRQ EC! \n");
		    	panic!();
		    }
		}	
		return;
	}
	if irq_bank_0 != 0 {
		match irq_bank_0 {
			ic::ARM_TIMER_IRQ => {
				// system timer
				// can be ignored
				return;
			},
			ic::ONE_OR_MORE_SET_IN_PENDING => {
				// caused by gpu side irq not being routed 
				// can be ignored
			},
			_ => {
				kprint!("some irq({:#b})! \n", irq_bank_0);
			}	
		}
	} 
	if irq_bank_1 != 0 {
		match irq_bank_1 {
			ic::ARM_TIMER_IRQ => {
				// system timer
				// can be ignored
				return;
			},
			_ => {
				kprint!("some irq b1({:#b})! \n", irq_bank_1);
			}	
		}
	}
	if irq_bank_2 != 0 {
		match irq_bank_2 {
			_ => {
				kprint!("some irq b2({:#b})! \n", irq_bank_2);
			}	
		}
	}
}

#[no_mangle]
pub fn uncommon_trap_handler() {
		kprint!("uncommon \n");	
}

#[panic_handler]
fn panic_handler(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}
