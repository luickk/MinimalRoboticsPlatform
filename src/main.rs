#![no_main]
#![no_std]

mod serial;
mod utils;
mod gicv2;
use serial::kprint;

core::arch::global_asm!(include_str!("asm/exc_vec.S"));
core::arch::global_asm!(include_str!("asm/adv_boot.S"));

#[no_mangle]
pub extern "C" fn kernel_main() {
	kprint!("Booting {:?} \n", "Kernel!");

	if gicv2::check_gicv2_avail() {
		gicv2::init_gic();
	} else {
		kprint!("gicv2 not available! \n")
	}

	// utils::test_sve_exc();
	kprint!("done \n");
}

#[no_mangle]
pub extern "C" fn common_trap_handler(exc: *const gicv2::ExceptionFrame) {
    // let iss = exc.esr_el1 as u:32: 25;
    // let il = exc.esr_el1 >> 25 as u1;
    // let ec = (exc.esr_el1 >> 26) as u32; // 26
    // let iss2 = exc.esr_el1 >> 32 as u5;
	kprint!("Interrupt/SErr \n");
	unsafe {
		kprint!("esr {:#b} \n", (*exc).esr_el1);	
	}
}

#[no_mangle]
pub fn uncommon_trap_handler() {}

#[panic_handler]
fn panic_handler(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}
