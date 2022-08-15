 #include "mmu.S"

// advanced boot
// is meant to setup the main kernel thread running in el1(erets to el2 and then in el1_entry_aarch64 to el1) with mmu disable, exc.vec. table setup, slave core disabled and fp/ smid operations enabled
.section ".text.boot"

.equ AArch64_EL1_SP1,  0x05    // EL1h

el1_entry_aarch64:
	//setup_mmu
	// setting up vector table (https://github.com/Xilinx/embeddedsw/blob/master/lib/bsp/standalone/src/arm/ARMv8/64bit/armclang/boot.S)
	ldr x0, = exception_vector_table
	msr vbar_el1, x0
	isb

	//  Enable FP/SIMD for el1
	mov	x0, #3 << 20
	msr	cpacr_el1, x0
	
 	// read cpu id, stop slave cores (https://github.com/bztsrc/raspi3-tutorial/blob/master/05_uart0/start.S )
    mrs x1, mpidr_el1
    and x1, x1, #3
    cbz x1, 2f
    // cpu id > 0, stop
1:  wfe
    b   1b
2:  // cpu id == 0

    // set top of stack just before our code (stack grows to a lower address per AAPCS64)
    ldr x1, = __stack_top
    mov sp, x1

    // clear bss
    ldr x1, =__bss_start
    ldr w2, =__bss_size
3:  cbz w2, 4f
    str xzr, [x1], #8
    sub w2, w2, #1
    cbnz w2, 3b

    // jump to C code, should not return

    // load km fn addr (without offset) in order to longjump to kernel vm
	// ldr	x2, =kernel_main
	// mov	x0, #SCTLR_MMU_ENABLED  
	// msr	sctlr_el1, x0
// 4:  bl  x2

4:  bl  kernel_main

// how to get from el3 to el1 is described here: https://developer.arm.com/documentation/102437/0100/Changing-Exception-levels
.globl	_start
_start:
	// todo => implement a53 errata

	// Configure SCR_EL3
	// -----------------
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