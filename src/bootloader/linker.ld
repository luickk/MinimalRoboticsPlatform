INCLUDE "src/mem_layout.ld"

ENTRY(_start)

SECTIONS {
    .boot : ALIGN(16) {
        *(.text.boot)
        *(.text);
        *(.text.*);
    } > ROM
    
    .exceptions : ALIGN(0x8) {
        *(.text.exc_vec);
    } > ROM

    .rodata : ALIGN(0x8) {
        *(.rodata);
        *(.rodata.*);
    } > ROM

    .bss : ALIGN(0x10) {
        _bl_bss_start = .;
        *(.bss.*);
        *(COMMON);
        _bl_bss_end = .;
    } > ROM

    .paging_tbl : ALIGN(0x00001000) {
        _bl_pg_dir = .;
        . += (3 * (1 << 12));
    } > ROM

    .data : {
        *(.data);
        *(.data.*);
    } > ROM
     
    .stack : ALIGN(16) {
        _bl_stack_bottom = .;
        . = . + 0x1000;
        _bl_stack_top = .;   
    } > ROM
}