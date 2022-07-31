#![no_main]
#![no_std]

mod serial;

core::arch::global_asm!(include_str!("boot.S"));

#[no_mangle]
pub extern "C" fn kernel_main() {
	serial::kprint!("Booting {:?}", "Kernel!");
}

#[panic_handler]
fn panic_handler(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}
