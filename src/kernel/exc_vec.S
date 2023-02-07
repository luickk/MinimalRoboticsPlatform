.section .text.exc_vec

// https://developer.arm.com/documentation/100933/0100/AArch64-exception-vector-table
.globl _exception_vector_table
.balign 0x80
_exception_vector_table:
    b _el1Sp0Sync // el1_sp0_sync

.balign 0x80
    b _el1Sp0Irq // el1_sp0_irq

.balign 0x80
    b _el1Sp0Fiq // el1_sp0_fiq

.balign 0x80
    b el1Sp0Err // el1_sp0_error


.balign 0x80
    b _el1Sync // el1Sync 

.balign 0x80
    b _el1Irq // el1Irq

.balign 0x80
    b _el1Fiq // el1Fiq

.balign 0x80
    b _el1Err // el1Error


.balign 0x80
    b _el0Sync // el0_sync

.balign 0x80
    b _el0Irq // el0_irq

.balign 0x80
    b _el0Fiq // el0_fiq

.balign 0x80
    b _el0Err // el0_error


.balign 0x80
    b _el032Sync // el0_32_sync

.balign 0x80
    b _el032Irq // el0_32_irq

.balign 0x80
    b _el032Fiq // el0_32_fiq

.balign 0x80
    b _el032Err // el0_32_error

.balign 0x80

.macro SAVE_CPU_CONTEXT
    // storing CpuContext struct(src/arm/CpuContext.zig) on stack
    stp q1, q0, [sp, #-32]!
    stp q3, q2, [sp, #-32]!
    stp q5, q4, [sp, #-32]!
    stp q7, q6, [sp, #-32]!
    stp q9, q8, [sp, #-32]!
    stp q11, q10, [sp, #-32]!
    stp q13, q12, [sp, #-32]!
    stp q15, q14, [sp, #-32]!
    stp q17, q16, [sp, #-32]!
    stp q19, q18, [sp, #-32]!
    stp q21, q20, [sp, #-32]!
    stp q23, q22, [sp, #-32]!
    stp q25, q24, [sp, #-32]!
    stp q27, q26, [sp, #-32]!
    stp q29, q28, [sp, #-32]!
    stp q31, q30, [sp, #-32]!
    // gp regs
    stp x1, x0, [sp, #-16]!
    stp x3, x2, [sp, #-16]!
    stp x5, x4, [sp, #-16]!
    stp x7, x6, [sp, #-16]!
    stp x9, x8, [sp, #-16]!
    stp x11, x10, [sp, #-16]!
    stp x13, x12, [sp, #-16]!
    stp x15, x14, [sp, #-16]!
    stp x17, x16, [sp, #-16]!
    stp x19, x18, [sp, #-16]!
    stp x21, x20, [sp, #-16]!
    stp x23, x22, [sp, #-16]!
    stp x25, x24, [sp, #-16]!
    stp x27, x26, [sp, #-16]!
    stp x29, x28, [sp, #-16]!

    // sys regs
    mov x1, sp
    stp x1, x30, [sp, #-16]!
    mov x0, fp
    mrs x3, elr_el1
    stp x3, x0, [sp, #-16]!
    mrs x0, sp_el0

    // debug regs
    mrs x3, SPSel
    stp x3, x0, [sp, #-16]!
    mrs x0, far_el1
    mrs x3, esr_el1
    stp x0, x3, [sp, #-16]!
    mrs x0, CurrentEL
    lsr x0, x0, #2
    stp xzr, x0, [sp, #-16]!
.endm

.macro EXCEPTION_VECTOR int_type
    SAVE_CPU_CONTEXT
    // bl disableIrq
    
    // set stack as arg
    ldr x1, #\int_type
    mov x0, sp
    bl trapHandler
    
    // bl enableIrq
    // restoreContextFromStack are fns exported from CpuContext.zig
    b _restoreContextWithoutSwitchFromSp
.endm

_el1Sp0Sync:
EXCEPTION_VECTOR el1Sp0Sync
_el1Sp0Irq:
EXCEPTION_VECTOR el1Sp0Irq
_el1Sp0Fiq:
EXCEPTION_VECTOR el1Sp0Fiq
_el1Sp0Err:
EXCEPTION_VECTOR el1Sp0Err

_el1Sync:
EXCEPTION_VECTOR el1Sync
_el1Irq:
EXCEPTION_VECTOR el1Irq
_el1Fiq:
EXCEPTION_VECTOR el1Fiq
_el1Err:
EXCEPTION_VECTOR el1Err

_el0Sync:
EXCEPTION_VECTOR el0Sync
_el0Irq:
EXCEPTION_VECTOR el0Irq
_el0Fiq:
EXCEPTION_VECTOR el0Fiq
_el0Err:
EXCEPTION_VECTOR el0Err

_el032Sync:
EXCEPTION_VECTOR el032Sync
_el032Irq:
EXCEPTION_VECTOR el032Irq
_el032Fiq:
EXCEPTION_VECTOR el032Fiq
_el032Err:
EXCEPTION_VECTOR el032Err

