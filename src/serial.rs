use core::fmt;

const MMIO_SERIAL: *mut u64 = (0x3F20_1000) as *mut u64;

pub struct SerialWrite;
impl SerialWrite {
	pub fn print_args(args: fmt::Arguments<'_>) {
		fmt::write(&mut SerialWrite{}, args).unwrap();
	}

	fn print_str(inp: &str) {
		for c in inp.as_bytes() {
			SerialWrite::put_char(*c);
		}
	}

	fn put_char(ch: u8) {
		unsafe {
			*MMIO_SERIAL = ch as u64;	
		} 
	}
}
impl fmt::Write for SerialWrite {
    fn write_str(&mut self, formatted_string: &str) -> fmt::Result {
    	SerialWrite::print_str(formatted_string);
		Ok(())
    }
}

macro_rules! kprint {
    ($($arg:tt)*) => {
        $crate::serial::SerialWrite::print_args(format_args!($($arg)*))
    };
}
pub(crate) use kprint;
