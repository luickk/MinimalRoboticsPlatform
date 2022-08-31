INCLUDE "src/mem_layout.ld"

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

    .paging_tbl : ALIGN(0x00001000) {
        _pg_dir = .;
        . += (3 * (1 << 12));
        _id_mapped_dir = .;
        . += (3 * (1 << 12));
    } > BOOT_ROM
}