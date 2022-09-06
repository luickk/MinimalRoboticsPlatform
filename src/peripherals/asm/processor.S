// all dcache inval is from linux codebase
.macro	dcache_line_size, reg, tmp
	lsr	\tmp, \tmp, #16
	and	\tmp, \tmp, #0xf // cache line sizce encoding
	mov	\reg, #4 // bytes per word
	lsl \reg, \reg, \tmp
	// mov	\reg, \reg, lsl \tmp // actual cache line size
.endm

.global _dcache_inval_poc
_dcache_inval_poc:
	dcache_line_size x2, x3
	sub	x3, x2, #1
	tst	x1, x3	// end cache line aligned?
	bic	x1, x1, x3
	b.eq	1f
	dc	civac, x1 // clean & invalidate D / U line
1:	tst	x0, x3 // start cache line aligned?
	bic	x0, x0, x3
	b.eq	2f
	dc	civac, x0 // clean & invalidate D / U line
	b	3f
2:	dc	ivac, x0 // invalidate D / U line
3:	add	x0, x0, x2
	cmp	x0, x1
	b.lo	2b
	dsb	sy
	ret