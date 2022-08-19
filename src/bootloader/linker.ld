ENTRY(_start)

SECTIONS
{
    . = 0x800;
    .boot : {
        *(.text.boot)
        *(.text);
        *(.text.*);
        _boot_sizeof = SIZEOF(.boot);
    }

    .rodata : ALIGN(0x8) {
        *(.rodata);
        *(.rodata.*);
    }

    .data : {
        *(.data);
        *(.data.*);
    }

    .bss : ALIGN(0x10) {
        _bss_start = .;
        *(.bss.*);
        *(COMMON);
        _bss_end = .;
    }

    .exceptions : ALIGN(0x8) {
        *(.text.exc_vec);
    }
        
    .paging_tbl : ALIGN(0x00001000) {
        _pg_dir = .;
        . += (3 * (1 << 12));
    }

    .stack : ALIGN(16) {
        _stack_bottom = .;
        . = . + 0x1000;
        _stack_top = .;   
    }
}