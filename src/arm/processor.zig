const board = @import("board");
const std = @import("std");
const AddrSpace = board.boardConfig.AddrSpace;

pub const ExceptionLevels = enum { el0, el1, el2, el3 };

// todo => remove params and custom type
pub fn ProccessorRegMap(curr_address_space: AddrSpace, curr_el: ExceptionLevels, curr_secure: bool) type {
    _ = curr_address_space;
    _ = curr_secure;
    return struct {
        pub const TcrReg = packed struct {
            t0sz: u6 = 0,
            reserved0: bool = false,
            epd0: bool = false,
            irgno0: u2 = 0,
            orgn0: u2 = 0,
            sh0: u2 = 0,
            tg0: u2 = 0,
            t1sz: u6 = 0,
            a1: bool = false,
            epd1: bool = false,
            irgn1: u2 = 0,
            orgn1: u2 = 0,
            sh1: u2 = 0,
            tg1: u2 = 0,
            ips: u3 = 0,
            reserved1: bool = false,
            as: bool = false,
            tbi0: bool = false,
            tbi1: bool = false,
            ha: bool = false,
            hd: bool = false,
            hpd0: bool = false,
            hpd1: bool = false,
            hwu059: bool = false,
            hwu060: bool = false,
            hwu061: bool = false,
            hwu062: bool = false,
            hwu159: bool = false,
            hwu160: bool = false,
            hwu161: bool = false,
            hwu162: bool = false,
            tbid0: bool = false,
            tbid1: bool = false,
            nfd0: bool = false,
            nfd1: bool = false,
            e0pd0: bool = false,
            e0pd1: bool = false,
            tcma0: bool = false,
            tcma1: bool = false,
            ds: bool = false,
            reserved2: u4 = 0,

            pub fn asInt(self: TcrReg) usize {
                return @bitCast(u64, self);
            }
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
            pub fn calcTxSz(gran: board.boardConfig.GranuleParams) u6 {
                // in bits
                const addr_space_indicator = 12;
                const addr_bsize = @bitSizeOf(usize);
                const bits_per_level = std.math.log2(gran.table_size);
                const n_lvl = @enumToInt(gran.lvls_required) + 1;
                return @truncate(u6, addr_bsize - (addr_space_indicator + (n_lvl * bits_per_level)));
            }
        };
        pub const MairReg = packed struct {
            attr0: u8 = 0,
            attr1: u8 = 0,
            attr2: u8 = 0,
            attr3: u8 = 0,
            attr4: u8 = 0,
            attr5: u8 = 0,
            attr6: u8 = 0,
            attr7: u8 = 0,

            pub fn asInt(self: MairReg) usize {
                return @bitCast(u64, self);
            }

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
        pub const SctlrEl = struct {
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
            var val = SctlrEl.readSctlrEl(el);
            val |= 1 << 0;
            SctlrEl.setSctlrEl(el, val);
            asm volatile ("isb");
        }

        pub inline fn disableMmu(comptime el: ExceptionLevels) void {
            var val = SctlrEl.readSctlrEl(el);
            val &= ~(1 << 0);
            SctlrEl.setSctlrEl(el, val);
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

        pub inline fn nop() void {
            asm volatile ("nop");
        }

        // has to happen at el3
        pub fn isSecState() bool {
            if (curr_el != .elr)
                @compileError("can only read security state in el3");
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
