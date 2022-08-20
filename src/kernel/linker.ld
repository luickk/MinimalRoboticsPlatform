ENTRY(kernel_main)
SECTIONS
{
    . = 0xffff000000000000;
    . = ALIGN(0x8);
    .exceptions : AT(0x0) {
        *(.text.exc_vec);
    }

    .text : {
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

    .stack : ALIGN(16) {
        _stack_bottom = .;
        . = . + 0x1000;
        _stack_top = .;   
    }
}