ENTRY(kernel_main)

SECTIONS {
    . = 0xffff000000000000 + {@zig};

    .text : ALIGN(16) {
        *(.text.kernel_main);
        *(.text.);
        *(.text.*);
    }

    .exceptions : ALIGN(0x8) {
        *(.text.exc_vec);
    }

    .rodata : ALIGN(0x8) {
        *(.rodata);
        *(.rodata.*);
    }

    .bss (NOLOAD) : ALIGN(16) {
        _bss_start = .;
        *(.bss.*);
        *(COMMON);
        _bss_end = .;
    }

    .paging_tbl (NOLOAD) : ALIGN(0x00001000) {
        _kernel_ttbr1_dir = .;
        . += (600 * (1 << 12));
        _user_ttbr0_dir = .;
        . += (600 * (1 << 12));
    }

    .data : {
        *(.data);
        *(.data.*);
    }

    .stack (NOLOAD) : ALIGN(16) {
        _stack_bottom = .;
        . = . + 0x1000;
        _stack_top = .;
    }
}