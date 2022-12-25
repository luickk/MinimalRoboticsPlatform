ENTRY(_start)

SECTIONS {
    . = {@zig};

    _bl_bin_start = .;
    
    .text : ALIGN(16) {
        *(.text.boot)
    }
    .exceptions : ALIGN(0x8) {
        *(.text.exc_vec);
    }
    # The data section needs to be located before the bootloader because in case the board doesn't have rom, 
    # the bootloader copies the kernel (which is embedde in the .rodata section) to "itself" (to the start or addr).
    # in that case, the bootloader code has to be located behind the kernel (in the .rodata section) to not overwrite itself and corrupt the copying
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