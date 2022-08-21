INCLUDE "src/mem_layout.ld"

ENTRY(kernel_main)
SECTIONS {
    .text : ALIGN(16) {
        *(.text.kernel_main);
        *(.text.;
        *(.text.*);
    } > ROM

    .exceptions : ALIGN(0x8) {
        *(.text.exc_vec);
    } > ROM


    .rodata : ALIGN(0x8) {
        *(.rodata);
        *(.rodata.*);
    } > ROM

    .data : {
        *(.data);
        *(.data.*);
    } > ROM

    .bss : ALIGN(16) {
        _bss_start = .;
        *(.bss.*);
        *(COMMON);
        _bss_end = .;
    } > ROM

    .paging_tbl : ALIGN(0x1000) {
        _pg_dir = .;
        . += (3 * (1 << 12));
    } > ROM

    .stack : ALIGN(16) {
        _stack_bottom = .;
        . = . + 0x1000;
        _stack_top = .;   
    } > ROM
}