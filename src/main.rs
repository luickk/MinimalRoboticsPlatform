#![no_main]
#![no_std]

mod serial;
mod utils;
mod ic;
mod ic_handler;

use serial::kprint;

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
pub extern "C" fn irq_elx_spx() {}

#[no_mangle]
pub extern "C" fn irq_handler(exc: *const ic::ExceptionFrame) {
	ic_handler::ic_handle(exc);
}

#[panic_handler]
fn panic_handler(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}
