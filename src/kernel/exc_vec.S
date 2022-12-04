// from https://github.com/lowenware/leos-kernel/blob/master/src/aarch64/exceptions.s

.section .text.exc_vec

.macro EXCEPTION_VECTOR handler int_type
    // saveCurrContextOnStack & restoreContextFromStack are fns exported from cpuContext.zig
    ldr x0, #\int_type
    bl saveCurrContextOnStack

    // set stack as arg
    mov x0, sp
    bl \handler
        
    bl restoreContextFromStack
    eret
.endm

// https://developer.arm.com/documentation/100933/0100/AArch64-exception-vector-table
.globl _exception_vector_table
.balign 0x80
_exception_vector_table:

    EXCEPTION_VECTOR irqElxSpx elxSpx // el1_sp0_sync

.balign 0x80
    EXCEPTION_VECTOR irqElxSpx elxSpx // el1_sp0_irq

.balign 0x80
    EXCEPTION_VECTOR irqElxSpx elxSpx // el1_sp0_fiq

.balign 0x80
    EXCEPTION_VECTOR irqElxSpx elxSpx // el1_sp0_error


.balign 0x80
    EXCEPTION_VECTOR irqHandler el1Sync // el1Sync (spx) selected bc issue I'm debugging is a sync exception

.balign 0x80
    EXCEPTION_VECTOR irqHandler el1Irq // el1Irq

.balign 0x80
    EXCEPTION_VECTOR irqHandler el1Fiq // el1Fiq

.balign 0x80
    EXCEPTION_VECTOR irqHandler el1Err // el1Error


.balign 0x80
    EXCEPTION_VECTOR irqElxSpx elxSpx // el0_sync

.balign 0x80
    EXCEPTION_VECTOR irqElxSpx elxSpx // el0_irq

.balign 0x80
    EXCEPTION_VECTOR irqElxSpx elxSpx // el0_fiq

.balign 0x80
    EXCEPTION_VECTOR irqElxSpx elxSpx // el0_error


.balign 0x80
    EXCEPTION_VECTOR irqElxSpx elxSpx // el0_32_sync

.balign 0x80
    EXCEPTION_VECTOR irqElxSpx elxSpx // el0_32_irq

.balign 0x80
    EXCEPTION_VECTOR irqElxSpx elxSpx // el0_32_fiq

.balign 0x80
    EXCEPTION_VECTOR irqElxSpx elxSpx // el0_32_error

.balign 0x80