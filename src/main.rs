#![feature(lang_items)]
#![feature(no_core)]
#![no_core]

#![no_std]
#![no_main]

// lang items required by the compiler
#[lang = "sized"]
pub trait Sized {}
#[lang = "copy"]
pub trait Copy {}

const MMIO_SERIAL: *mut u64 = 0x09000000 as *mut u64;

fn put_char(ch: u8) {
	unsafe {
		*MMIO_SERIAL = ch as u64;	
	} 
}


pub fn kprint(inp: &str) {
	let mut i: usize = 0;
    while i <= inp.len() {
        put_char(inp.as_bytes()[i]);
        i = i + 1 as usize;
    }
}

pub extern "C" fn kernel_main() {
	kprint("test \n");
}