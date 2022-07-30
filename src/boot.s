.global _main
_main:
    ldr x30, = _stack_top
    mov sp, x30
    bl kernel_main
    b .
