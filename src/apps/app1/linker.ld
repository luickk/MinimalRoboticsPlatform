ENTRY(app_main)

SECTIONS {
    . = 0x0;
    
    .text : ALIGN(16) {
        *(.text.main)
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
}