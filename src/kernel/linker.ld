ENTRY(kernel_main)

SECTIONS {
    # exaplatnation as to why this exact address can be found in the readme under mmu
    . = {@zig};

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
    
    .kernel_space (NOLOAD) : ALIGN(8)  {
        _kernel_space_start = .;
    }

}