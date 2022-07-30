#![no_std]
#![no_main]

mod serial;

core::arch::global_asm!(include_str!("boot.S"));

#[no_mangle]
pub extern "C" fn kernel_main() {
	serial::kprint("test \n");
}

#[panic_handler]
fn panic_handler(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}
