// advanced boot
// is meant to setup the main kernel thread running in el1 with mmu disable, exc.vec. table setup, slave core disabled and fp/ smid operations enabled
.section ".text.boot"

.globl	_start

_start:
	// clearing gprs
	mov	x0, #0
	mov	x1, #0
	mov	x2, #0
	mov	x3, #0
	mov	x4, #0
	mov	x5, #0
	mov	x6, #0
	mov	x7, #0
	mov	x8, #0
	mov	x9, #0
	mov	x10, #0
	mov	x11, #0
	mov	x12, #0
	mov	x13, #0
	mov	x14, #0
	mov	x15, #0
	mov	x16, #0
	mov	x17, #0
	mov	x18, #0
	mov	x19, #0
	mov	x20, #0
	mov	x21, #0
	mov	x22, #0
	mov	x23, #0
	mov	x24, #0
	mov	x25, #0
	mov	x26, #0
	mov	x27, #0
	mov	x28, #0
	mov	x29, #0
	mov	x30, #0
	
	// from https://stackoverflow.com/questions/46194098/armv8-changing-from-el3-to-el1-secure
	mov x0, xzr
	orr x0, x0, #(1 << 29) // Checking http://infocenter.arm.com/help/index.jsp?topic=/com.arm.doc.ddi0500d/CIHDIEBD.html
	orr x0, x0, #(1 << 28) // Bits 29,28,23,22,20,11 should be 1 (res1 on documentation)
	orr x0, x0, #(1 << 23)
	orr x0, x0, #(1 << 22)
	orr x0, x0, #(1 << 20)
	orr x0, x0, #(1 << 11)
	msr sctlr_el1, x0

	// setting up vector table (https://github.com/Xilinx/embeddedsw/blob/master/lib/bsp/standalone/src/arm/ARMv8/64bit/armclang/boot.S)
	ldr x0, = exception_vector_table
	msr vbar_el1, x0
	isb

	// Disable MMU
	mov	x1, #0x0
	msr	sctlr_el1, x1
	isb

	 //  Enable FP/SIMD for el1
	mov	x0, #3 << 20
	msr	cpacr_el1, x0
	
 	// read cpu id, stop slave cores (https://github.com/bztsrc/raspi3-tutorial/blob/master/05_uart0/start.S )
    mrs     x1, mpidr_el1
    and     x1, x1, #3
    cbz     x1, 2f
    // cpu id > 0, stop
1:  wfe
    b       1b
2:  // cpu id == 0

    // set top of stack just before our code (stack grows to a lower address per AAPCS64)
    ldr     x1, =_start
    mov     sp, x1

    // clear bss
    ldr     x1, =__bss_start
    ldr     w2, =__bss_size
3:  cbz     w2, 4f
    str     xzr, [x1], #8
    sub     w2, w2, #1
    cbnz    w2, 3b

    // jump to C code, should not return
4:  bl      kernel_main
	// todo => implement a53 errata

