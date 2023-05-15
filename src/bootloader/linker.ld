ENTRY(_start)

SECTIONS {
    . = {@zig};

    _bl_bin_start = .;
    
    .text : ALIGN(16) {
        *(.text.boot)
    }
    .exceptions : ALIGN(0x800) {
        *(.text.exc_vec);
    }
    
    .rodata : ALIGN(0x8) {
        *(.rodata);
        *(.rodata.*);
    }
    
    .bootloader : ALIGN(16) {
        *(.text.);
        *(.text.*);
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

    .bl_end (NOLOAD) : ALIGN(8)  {
        _bl_end = .;
    }
}