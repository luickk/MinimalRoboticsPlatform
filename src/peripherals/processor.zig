pub inline fn enableMmu() void {
    const mmu_en: usize = 1 << 0;
    asm volatile ("msr sctlr_el1, %[mmu_en]"
        :
        : [mmu_en] "rax" (mmu_en),
    );
    asm volatile ("isb");
}

pub inline fn branchToAddr(addr: u64) void {
    asm volatile ("br %[pc_addr]"
        :
        : [pc_addr] "rax" (addr),
    );
}

pub inline fn disableMmu() void {
    const mmu_en: usize = 0;
    asm volatile ("msr sctlr_el1, %[mmu_en]"
        :
        : [mmu_en] "rax" (mmu_en),
    );
}

pub fn setTTBR1(addr: usize) void {
    asm volatile ("msr ttbr1_el1, %[addr]"
        :
        : [addr] "rax" (addr),
    );
}

pub fn invalidateDCache(pg_dir_addr: usize, pg_dir_size: usize) void {
    asm volatile ("mov x0, %[addr]"
        :
        : [addr] "rax" (pg_dir_addr),
    );
    asm volatile ("mov x1, %[addr]"
        :
        : [addr] "rax" (pg_dir_addr + pg_dir_size),
    );

    asm volatile ("bl _dcache_inval_poc");
}

pub inline fn isb() void {
    asm volatile ("isb");
}

pub inline fn exceptionSvc() void {
    // Supervisor call to allow application code to call the OS.  It generates an exception targeting exception level 1 (EL1).
    asm volatile ("svc #0xdead");
}

pub fn getCurrentEl() u64 {
    var x: u64 = asm ("mrs %[curr], CurrentEL"
        : [curr] "=r" (-> u64),
    );
    return x >> 2;
}

pub fn panic() noreturn {
    while (true) {}
}
