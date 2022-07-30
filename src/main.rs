#![no_std]
#![no_main]

#[panic_handler]
fn panic_handler(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}

const MMIO_SERIAL: *mut u64 = 0x09000000 as *mut u64;


core::arch::global_asm!(include_str!("boot.S"));

fn put_char(ch: u8) {
	unsafe {
		*MMIO_SERIAL = ch as u64;	
	} 
}

pub fn kprint(inp: &str) {
	let mut i: usize = 0;
	let inp_bytes = inp.as_bytes();
    while i <= inp.len() {
        put_char(inp_bytes[i]);
        i += 1;
    }
}

#[no_mangle]
pub extern "C" fn kernel_main() {
	kprint("test \n");
}