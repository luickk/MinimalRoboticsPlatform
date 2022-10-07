// todo => write generic functions

// pub const ExceptionLevels = enum { el0, el1, el2, el3 };
// pub fn Proccessor(el: ExceptionLevels, secure: bool,) type {
//     return struct {};
// }
pub inline fn setTcrEl1(val: usize) void {
    asm volatile ("msr tcr_el1, %[val]"
        :
        : [val] "rax" (val),
    );
}

pub inline fn setMairEl1(val: usize) void {
    asm volatile ("msr mair_el1, %[val]"
        :
        : [val] "rax" (val),
    );
}

pub fn readTCRel1() usize {
    var x: usize = asm ("mrs %[curr], tcr_el1"
        : [curr] "=r" (-> usize),
    );
    return x;
}

pub inline fn enableMmu() void {
    const mmu_en: usize = 1 << 0;
    asm volatile ("msr sctlr_el1, %[mmu_en]"
        :
        : [mmu_en] "rax" (mmu_en),
    );
    asm volatile ("isb");
}

pub inline fn setSp(addr: usize) void {
    asm volatile ("mov sp, %[addr]"
        :
        : [addr] "rax" (addr),
    );
    isb();
}

pub inline fn branchToAddr(addr: usize) void {
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

pub fn invalidateMmuTlbEl1() void {
    // https://developer.arm.com/documentation/ddi0488/c/system-control/aarch64-register-summary/aarch64-tlb-maintenance-operations
    asm volatile ("TLBI VMALLE1IS");
}

pub fn setTTBR1(addr: usize) void {
    asm volatile ("msr ttbr1_el1, %[addr]"
        :
        : [addr] "rax" (addr),
    );
}

pub fn setTTBR0(addr: usize) void {
    asm volatile ("msr ttbr0_el1, %[addr]"
        :
        : [addr] "rax" (addr),
    );
}

pub fn invalidateCache() void {
    asm volatile ("IC IALLUIS");
}

pub inline fn isb() void {
    asm volatile ("isb");
}
pub inline fn dsb() void {
    asm volatile ("dsb SY");
}

pub inline fn exceptionSvc() void {
    // Supervisor call to allow application code to call the OS.  It generates an exception targeting exception level 1 (EL1).
    asm volatile ("svc #0xdead");
}

pub fn getCurrentEl() usize {
    var x: usize = asm ("mrs %[curr], CurrentEL"
        : [curr] "=r" (-> usize),
    );
    return x >> 2;
}

// has to happen at el3
pub fn isSecState() bool {
    // reading NS bit
    var x: usize = asm ("mrs %[curr], scr_el3"
        : [curr] "=r" (-> usize),
    );
    return (x & (1 << 0)) != 0;
}

pub fn panic() noreturn {
    while (true) {}
}
