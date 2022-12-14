.section ".text.boot"

.equ AArch64_EL1_SP1,  0x05    // EL1h


// how to get from el3 to el1 is described here: https://developer.arm.com/documentation/102437/0100/Changing-Exception-levels
.globl	_start
_start:
	// checking for secure state
	mrs x1, scr_el3
	tbnz  x1, 0, proc_hang

	mrs	x0, mpidr_el1		
	and	x0, x0,#0xFF // Check processor id
	cbz	x0, master // Hang for all non-primary CPU
	b	proc_hang
	
el1_entry_aarch64:
	ldr x0, = _exception_vector_table
	msr vbar_el1, x0
	isb

	//  Enable FP/SIMD for el1
	mov	x0, #3 << 20
	msr	cpacr_el1, x0

	// clear bss section
    adr	x0, _bss_start
	adr	x1, _bss_end
	sub	x1, x1, x0
	bl 	memzero
	isb

	bl  bl_main

master:
	// disabling mmu
	mov	x1, #0x0
	msr	sctlr_el1, x1
	isb

	// Configure SCR_EL3
	// -----------------dd
	mov w1, #0      // Initial value of register is unknown
	orr w1, w1, #(1 << 11)  // set ST bit (disable trapping of timer control registers)
	orr w1, w1, #(1 << 10)  // set RW bit (next lower EL in aarch64)
	// orr  w1, w1, #(1 << 3)   // Set EA bit (SError routed to EL3)
	// orr  w1, w1, #(1 << 2)   // Set FIQ bit (FIQs routed to EL3)
	// orr  w1, w1, #(1 << 1)   // Set IRQ bit (IRQs routed to EL3)
	msr SCR_EL3, x1

	 // Initialize SCTLR_EL1
	// --------------------
	// SCTLR_EL1 has an unknown reset value and must be configured
	// before we can enter EL1
	msr SCTLR_EL1, xzr

	ldr x0, =el1_entry_aarch64
	ldr x1, =AArch64_EL1_SP1
	msr ELR_EL3, x0 // where to branch to when exception completes
	msr SPSR_EL3, x1 // set the program state for this point to a known value

	eret

proc_hang: 
	b proc_hang

.globl memzero
memzero:
    str xzr, [x0], #8
    subs x1, x1, #8
    b.gt memzero
    br lr
