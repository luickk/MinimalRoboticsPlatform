MEMORY {
  BOOT_ROM : ORIGIN = 0x0, LENGTH = 502404
  KERNEL_ROM : ORIGIN = 502404, LENGTH = 502404
  RAM : org = 1004808, l = 1M
}

_bootrom_start = ORIGIN(BOOT_ROM);
_bootrom_end = ORIGIN(BOOT_ROM) + LENGTH(BOOT_ROM);
_kernelrom_start = ORIGIN(KERNEL_ROM);
_kernelrom_end = ORIGIN(KERNEL_ROM)+LENGTH(KERNEL_ROM);
_ram_start = ORIGIN(RAM);
_ram_end = ORIGIN(RAM)+LENGTH(RAM);

ENTRY(_start)

SECTIONS {
    .boot : ALIGN(16) {
        *(.text.boot)
        *(.text.);
        *(.text.*);
    } > BOOT_ROM

    .exceptions : ALIGN(0x8) {
        *(.text.exc_vec);
    } > BOOT_ROM

    .got : { 
        *(.got.plt);
        *(.got);
    } > BOOT_ROM

    .rodata : ALIGN(0x8) {
        *(.rodata);
        *(.rodata.*);
    } > BOOT_ROM

    .bss : ALIGN(0x10) {
        _bss_start = .;
        *(.bss.*);
        *(COMMON);
        _bss_end = .;
    } > BOOT_ROM

    .data : {
        *(.data);
        *(.data.*);
    } > BOOT_ROM
     
    .stack : ALIGN(16) {
        _stack_bottom = .;
        . = . + 0x1000;
        _stack_top = .;   
    } > BOOT_ROM

    .paging_tbl : ALIGN(0x1000) {
        _pg_dir = .;
        . += (3 * (1 << 12));
        _id_mapped_dir = .;
        . += (3 * (1 << 12));
        _test_dir = .;
        . += (3 * (1 << 12));
    } > BOOT_ROM
}