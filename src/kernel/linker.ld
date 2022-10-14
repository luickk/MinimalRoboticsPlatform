ENTRY(kernel_main)

SECTIONS {
    . = 0xffff000000000000 + {@zig};

    .text : ALIGN(16) {
        *(.text.kernel_main);
    }

    .exceptions : ALIGN(0x8) {
        *(.text.exc_vec);
    }

    .kernel : ALIGN(16) {
        *(.text.);
        *(.text.*);
    }

    .rodata : ALIGN(0x8) {
        *(.rodata);
        *(.rodata.*);
    }

    .bss : ALIGN(16) {
        _bss_start = .;
        *(.bss.*);
        *(COMMON);
        _bss_end = .;
    }

    .data : {
        *(.data);
        *(.data.*);
    }

    .stack : ALIGN(16) {
        _stack_bottom = .;
        . = . + {@zig};
        _stack_top = .;
    }
    
    .paging_tbl (NOLOAD) : ALIGN(0x00001000)  {
        _ttbr1 = .;
        . = . + {@zig};
        _ttbr0 = .;
    }
}