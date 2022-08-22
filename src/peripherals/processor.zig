pub fn enableMmu() void {

    // SCTLR_MMU_ENABLED
    // ldr  x2, = bl_main
    // mov  x0, (1 << 0)
    // msr  sctlr_el1, x0
    // br x2
    const mmu_en: usize = 1 << 0;
    asm volatile ("msr sctlr_el1, %[mmu_en]"
        :
        : [mmu_en] "rax" (mmu_en),
    );
}

pub fn branchToAddr(addr: u64) void {
    asm volatile ("br %[pc_addr]"
        :
        : [pc_addr] "rax" (addr),
    );
}

pub fn disableMmu() void {

    // SCTLR_MMU_ENABLED
    // ldr  x2, = bl_main
    // mov  x0, (1 << 0)
    // msr  sctlr_el1, x0
    // br x2
    const mmu_en: usize = 0;
    asm volatile ("msr sctlr_el1, %[mmu_en]"
        :
        : [mmu_en] "rax" (mmu_en),
    );
}

pub fn exceptionSvc() void {
    // Supervisor call to allow application code to call the OS.  It generates an exception targeting exception level 1 (EL1).
    asm volatile ("svc #0xdead");
}

pub fn getCurrentEl() u64 {
    var x: u64 = asm ("mrs %[curr], CurrentEL"
        : [curr] "=r" (-> u64),
    );
    return x >> 2;
}

pub fn panic() void {}
