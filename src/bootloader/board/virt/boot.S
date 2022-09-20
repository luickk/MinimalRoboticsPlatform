.section ".text.boot"

// how to get from el3 to el1 is described here: https://developer.arm.com/documentation/102437/0100/Changing-Exception-levels
.globl	_start
_start:
	mrs	x0, mpidr_el1		
	and	x0, x0,#0xFF // Check processor id
	cbz	x0, master // Hang for all non-primary CPU
	b	master

// virt does directly boot to el1 on startup
master:
	// setting up vector table (https://github.com/Xilinx/embeddedsw/blob/master/lib/bsp/standalone/src/arm/ARMv8/64bit/armclang/boot.S)
	ldr x0, =_exception_vector_table
	msr vbar_el1, x0
	isb

	// disabling mmu
	mov	x1, #0x0
	msr	sctlr_el1, x1
	isb

	//  Enable FP/SIMD for el1
	mov	x0, #3 << 20
	msr	cpacr_el1, x0

    adr	x0, _bss_start
	adr	x1, _bss_end
	sub	x1, x1, x0
	bl 	memzero
	isb 

    // set top of stack just before our code (stack grows to a lower address per AAPCS64)
    ldr x1, = _stack_top
    mov sp, x1
	isb

	bl  bl_main

proc_hang: 
	b proc_hang

.globl memzero
memzero:
    str xzr, [x0], #8
    subs x1, x1, #8
    b.gt memzero
    br lr
