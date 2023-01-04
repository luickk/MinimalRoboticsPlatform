.section .text.exc_vec

.macro EXCEPTION_VECTOR handler int_type
    // saveCurrContextOnStack & restoreContextFromStack are fns exported from cpuContext.zig
    bl _saveCurrContextOnStack
    
    // set stack as arg
    ldr x1, #\int_type
    mov x0, sp
    bl \handler
    
    b _restoreContextFromStack
.endm

// https://developer.arm.com/documentation/100933/0100/AArch64-exception-vector-table
.globl _exception_vector_table
.balign 0x80
_exception_vector_table:
    EXCEPTION_VECTOR irqElxSpx el1Sp0Sync // el1_sp0_sync

.balign 0x80
    EXCEPTION_VECTOR irqElxSpx el1Sp0Irq // el1_sp0_irq

.balign 0x80
    EXCEPTION_VECTOR irqElxSpx el1Sp0Fiq // el1_sp0_fiq

.balign 0x80
    EXCEPTION_VECTOR irqElxSpx el1Sp0Err // el1_sp0_error


.balign 0x80
    EXCEPTION_VECTOR irqHandler el1Sync // el1Sync 

.balign 0x80
    EXCEPTION_VECTOR irqHandler el1Irq // el1Irq

.balign 0x80
    EXCEPTION_VECTOR irqHandler el1Fiq // el1Fiq

.balign 0x80
    EXCEPTION_VECTOR irqHandler el1Err // el1Error


.balign 0x80
    EXCEPTION_VECTOR irqElxSpx el0Sync // el0_sync

.balign 0x80
    EXCEPTION_VECTOR irqElxSpx el0Irq // el0_irq

.balign 0x80
    EXCEPTION_VECTOR irqElxSpx el0Fiq // el0_fiq

.balign 0x80
    EXCEPTION_VECTOR irqElxSpx el0Err // el0_error


.balign 0x80
    EXCEPTION_VECTOR irqElxSpx el032Sync // el0_32_sync

.balign 0x80
    EXCEPTION_VECTOR irqElxSpx el032Irq // el0_32_irq

.balign 0x80
    EXCEPTION_VECTOR irqElxSpx el032Fiq // el0_32_fiq

.balign 0x80
    EXCEPTION_VECTOR irqElxSpx el032Err // el0_32_error

.balign 0x80