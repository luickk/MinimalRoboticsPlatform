INCLUDE "src/mem_layout.ld"

ENTRY(kernel_main)

SECTIONS {
    .text : ALIGN(16) {
        *(.text.kernel_main);
        *(.text.);
        *(.text.*);
    } > KERNEL_ROM
    
    .exceptions : ALIGN(0x8) {
        *(.text.exc_vec);
    } > KERNEL_ROM

    .rodata : ALIGN(0x8) {
        *(.rodata);
        *(.rodata.*);
    } > RAM

    .bss : ALIGN(16) {
        _bss_start = .;
        *(.bss.*);
        *(COMMON);
        _bss_end = .;
    } > RAM

    .paging_tbl : ALIGN(0x00001000) {
        _pg_dir = .;
        . += (3 * (1 << 12));
    } > RAM

    .data : {
        *(.data);
        *(.data.*);
    } > RAM

    .stack : ALIGN(16) {
        _stack_bottom = .;
        . = . + 0x1000;
        _stack_top = .;   
    } > RAM
}