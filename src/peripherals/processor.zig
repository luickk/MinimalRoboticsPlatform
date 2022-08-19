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
