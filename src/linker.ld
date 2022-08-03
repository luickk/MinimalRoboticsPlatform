# from https://github.com/bztsrc/raspi3-tutorial/blob/master/05_uart0/link.ld
SECTIONS
{
    . = 0x80000;
    .text : { *(.text.boot) }
    . = ALIGN(0x800);
    .text.exceptions : { *(.text.exceptions) }
    .rodata : { *(.rodata .rodata.*) }
    .data : { *(.data .data.*) }
    .bss : {
        . = ALIGN(16);
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        __bss_end = .;
    }
    _end = .;
}
__bss_size = (__bss_end - __bss_start)>>3;