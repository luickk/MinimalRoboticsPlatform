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
        . = . + 0x1000;
        _stack_top = .;
    }
    
    # aligned by page size
    .paging_tbl : ALIGN(0x00001000)  {
        _kernel_ttbr1_dir = .;
        . += {@zig};
        _user_ttbr0_dir = .;
        . += {@zig};
    }
}