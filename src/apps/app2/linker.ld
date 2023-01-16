ENTRY(app_main)

SECTIONS {
    . = 0x0;
    
    .text : ALIGN(16) {
        *(.text.main)
        *(.text.);
        *(.text.*);
    }
    .rodata : ALIGN(0x8) {
        *(.rodata);
        *(.rodata.*);
    }
    .got : { 
        *(.got.plt);
        *(.got);
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