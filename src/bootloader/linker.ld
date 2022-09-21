ENTRY(_start)

SECTIONS {
    . = {@zig};

    .text : ALIGN(16) {
        *(.text.boot)
    }
    .exceptions : ALIGN(0x8) {
        *(.text.exc_vec);
    }
    .bootloader : ALIGN(16) {
        *(.text.);
        *(.text.*);
    }


    .got : { 
        *(.got.plt);
        *(.got);
    }

    .rodata : ALIGN(0x8) {
        *(.rodata);
        *(.rodata.*);
    }

    .bss : ALIGN(0x10) {
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

    .paging_tbl : ALIGN(0x1000) {
        _ttbr1_dir = .;
        . += (4 * (1 << 12));
        _ttbr0_dir = .;
        . += (4 * (1 << 12));
    }
    _kernelrom_start = .;
}