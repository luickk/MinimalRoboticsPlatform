const board = @import("board");
const AddrSpace = board.boardConfig.AddrSpace;

// todo => put all reg maps off cpu regs here!

pub const ExceptionLevels = enum { el0, el1, el2, el3 };

pub fn Proccessor(curr_address_space: AddrSpace, curr_el: ExceptionLevels, curr_secure: bool) type {
    _ = curr_address_space;
    _ = curr_el;
    _ = curr_secure;
    return struct {
        pub const tcr_el = struct {
            pub inline fn setTcrEl(comptime el: ExceptionLevels, val: usize) void {
                asm volatile ("msr tcr_" ++ @tagName(el) ++ ", %[val]"
                    :
                    : [val] "rax" (val),
                );
            }
            pub fn readTcrEl(comptime el: ExceptionLevels) usize {
                var x: usize = asm ("mrs %[curr], tcr_" ++ @tagName(el)
                    : [curr] "=r" (-> usize),
                );
                return x;
            }
        };
        pub const mair_el = struct {
            pub inline fn setMairEl(comptime el: ExceptionLevels, val: usize) void {
                asm volatile ("msr mair_" ++ @tagName(el) ++ ", %[val]"
                    :
                    : [val] "rax" (val),
                );
            }

            pub fn readTcrEl(comptime el: ExceptionLevels) usize {
                var x: usize = asm ("mrs %[curr], mair_" ++ @tagName(el)
                    : [curr] "=r" (-> usize),
                );
                return x;
            }
        };
        pub const sctlr_el = struct {
            pub inline fn setSctlrEl(comptime el: ExceptionLevels, val: usize) void {
                asm volatile ("msr sctlr_" ++ @tagName(el) ++ ", %[val]"
                    :
                    : [val] "rax" (val),
                );
            }

            pub fn readSctlrEl(comptime el: ExceptionLevels) usize {
                var x: usize = asm ("mrs %[curr], sctlr_" ++ @tagName(el)
                    : [curr] "=r" (-> usize),
                );
                return x;
            }
        };

        // enables for el0/1 for el1
        pub inline fn enableMmu(comptime el: ExceptionLevels) void {
            var val = sctlr_el.readSctlrEl(el);
            val |= 1 << 0;
            sctlr_el.setSctlrEl(el, val);
            asm volatile ("isb");
        }

        pub inline fn disableMmu(comptime el: ExceptionLevels) void {
            var val = sctlr_el.readSctlrEl(el);
            val &= ~(1 << 0);
            sctlr_el.setSctlrEl(el, val);
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
    };
}
