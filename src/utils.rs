pub fn test_sve_exc() {
	unsafe {
		core::arch::asm!("svc 0x80");
	}
}