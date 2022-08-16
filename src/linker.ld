# from https://github.com/bztsrc/raspi3-tutorial/blob/master/05_uart0/link.ld
SECTIONS
{
    . = 0xffff000000000000;
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
    . = ALIGN(0x00001000);
    pg_dir = .;
    .data.pgd : { . += (3 * (1 << 12)); }
    . = ALIGN(16);
    __stack_bottom = .;
    . = . + 0x1000;
    __stack_top = .;
}
__bss_size = (__bss_end - __bss_start)>>3;