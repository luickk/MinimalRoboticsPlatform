// from https://github.com/lowenware/leos-kernel/blob/master/src/aarch64/exceptions.s

.equ CONTEXT_SIZE, 264

.section .text.exc_vec

.macro EXCEPTION_VECTOR handler int_type
    sub sp, sp, #CONTEXT_SIZE

    // store general purpose registers
    stp x0, x1, [sp, #16 * 0]
    stp x2, x3, [sp, #16 * 1]
    stp x4, x5, [sp, #16 * 2]
    stp x6, x7, [sp, #16 * 3]
    stp x8, x9, [sp, #16 * 4]
    stp x10, x11, [sp, #16 * 5]
    stp x12, x13, [sp, #16 * 6]
    stp x14, x15, [sp, #16 * 7]
    stp x16, x17, [sp, #16 * 8]
    stp x18, x19, [sp, #16 * 9]
    stp x20, x21, [sp, #16 * 10]
    stp x22, x23, [sp, #16 * 11]
    stp x24, x25, [sp, #16 * 12]
    stp x26, x27, [sp, #16 * 13]
    stp x28, x29, [sp, #16 * 14]


    // store exception link register and exc. symptom reg
    ldr x0, \int_type
    mrs x1, esr_el1
    stp x0, x1, [sp, #16 * 15]
    
    mrs x0, elr_el1
    stp x0, x30, [sp, #16 * 16]

    mov x0, sp

    // call exception handler
    bl \handler
    
    // exit exception
    b .exit_exception
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


.exit_exception:
    // restore link register
    // ldr x30, [sp, #16 * 16]

    // restore exception link register and saved processor state register
    ldp x0, x30, [sp, #16 * 16]
    msr elr_el1, x0

    // restore general purpose registers
    ldp x28, x29, [sp, #16 * 14]
    ldp x26, x27, [sp, #16 * 13]
    ldp x24, x25, [sp, #16 * 12]
    ldp x22, x23, [sp, #16 * 11]
    ldp x20, x21, [sp, #16 * 10]
    ldp x18, x19, [sp, #16 * 9]
    ldp x16, x17, [sp, #16 * 8]
    ldp x14, x15, [sp, #16 * 7]
    ldp x12, x13, [sp, #16 * 6]
    ldp x10, x11, [sp, #16 * 5]
    ldp x8, x9, [sp, #16 * 4]
    ldp x6, x7, [sp, #16 * 3]
    ldp x4, x5, [sp, #16 * 2]
    ldp x2, x3, [sp, #16 * 1]
    ldp x0, x1, [sp, #16 * 0]

    // restore stack pointer
    add sp, sp, #CONTEXT_SIZE
    eret