pub fn read_from<T: Copy>(reg: usize) -> T {
	unsafe {
		let addr = reg as *mut T;
		return addr.read_volatile();	
	}
}

pub fn write_to<T>(reg: usize, val: T) {
	unsafe {
		let addr = reg as *mut T;
		addr.write_volatile(val);
	}
}

pub fn test_sve_exc() {
	unsafe {
		core::arch::asm!("svc 0xdead");
	}
}

pub fn get_current_el() -> u64 {
	let x: u64;
	unsafe {
	    core::arch::asm!("MRS {}, CurrentEL", out(reg) x);
	}
	x >> 2
}