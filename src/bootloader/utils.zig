pub fn enableMmu() void {

    // SCTLR_MMU_ENABLED
    // ldr	x2, = bl_main
    // mov	x0, (1 << 0)
    // msr	sctlr_el1, x0
    // br x2
    const mmu_en: usize = 1 << 0;
    asm volatile ("msr sctlr_el1, %[enable]"
        :
        : [mmu_en] "{rax}" (mmu_en),
    );
}
