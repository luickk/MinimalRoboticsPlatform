const board = @import("board");
const std = @import("std");
const AddrSpace = board.boardConfig.AddrSpace;

pub const ExceptionLevels = enum { el0, el1, el2, el3 };

pub const ProccessorRegMap = struct {
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
            return @as(u64, @bitCast(self));
        }
        pub inline fn setTcrEl(comptime el: ExceptionLevels, val: usize) void {
            asm volatile ("msr tcr_" ++ @tagName(el) ++ ", %[val]"
                :
                : [val] "r" (val),
            );
        }
        pub fn readTcrEl(comptime el: ExceptionLevels) usize {
            const x: usize = asm ("mrs %[curr], tcr_" ++ @tagName(el)
                : [curr] "=r" (-> usize),
            );
            return x;
        }
        pub fn calcTxSz(gran: board.boardConfig.Granule.GranuleParams) u6 {
            // in bits
            const addr_space_indicator = 12;
            const addr_bsize = @bitSizeOf(usize);
            const bits_per_level = std.math.log2(gran.table_size);
            const n_lvl = @intFromEnum(gran.lvls_required) + 1;
            return @as(u6, @truncate(addr_bsize - (addr_space_indicator + (n_lvl * bits_per_level))));
        }
    };
    pub const Esr_el1 = struct {
        pub const Ifsc = enum(u6) {
            addrSizeFaultLvl0 = 0b000000, // Address size fault, level 0 of translation or translation table base register.
            addrSizeFaultLvl1 = 0b000001, // Address size fault, level 1.
            addrSizeFaultLvl2 = 0b000010, // Address size fault, level 2.
            addrSizeFaultLvl3 = 0b000011, // Address size fault, level 3.
            transFaultLvl0 = 0b000100, // Translation fault, level 0.
            transFaultLvl1 = 0b000101, // Translation fault, level 1.
            transFaultLvl2 = 0b000110, // Translation fault, level 2.
            transFaultLvl3 = 0b000111, // Translation fault, level 3.
            accessFlagFaultLvl1 = 0b001001, // Access flag fault, level 1.
            accessFlagFaultLvl2 = 0b001010,
            accessFlagFaultLvl3 = 0b001011,
            accessFlagFaultLvl0 = 0b001000,
            permFaultLvl0 = 0b001100,
            permFaultLvl1 = 0b001101,
            permFaultLvl2 = 0b001110,
            permFaultLvl3 = 0b001111,
            syncExternalAbortNotOnTableWalk = 0b010000,
            syncExternalAbortNotOnTableWalkLvlN1 = 0b010011, // Synchronous External abort on translation table walk or hardware update of translation table, level -1.
            syncExternalAbortOnTableWalkLvl0 = 0b010100, // Synchronous External abort on translation table walk or hardware update of translation table, level 0.
            syncExternalAbortOnTableWalkLvl1 = 0b010101, // Synchronous External abort on translation table walk or hardware update of translation table, level 1.
            syncExternalAbortOnTableWalkLvl2 = 0b010110, // Synchronous External abort on translation table walk or hardware update of translation table, level 2.
            syncExternalAbortOnTableWalkLvl3 = 0b010111, // Synchronous External abort on translation table walk or hardware update of translation table, level 3.
            syncParityOrEccErrOnMemAccessOrWalk = 0b011000, // Synchronous parity or ECC error on memory access, not on translation table walk.
            syncParityOrEccErrOnMemAccessOrWalkLvlN1 = 0b011011, // Synchronous parity or ECC error on memory access on translation table walk or hardware update of translation table, level -1.
            syncParityOrEccErrOnMemAccessOrWalkLvl0 = 0b011100, // Synchronous parity or ECC error on memory access on translation table walk or hardware update of translation table, level 0.
            syncParityOrEccErrOnMemAccessOrWalkLvl1 = 0b011101, // Synchronous parity or ECC error on memory access on translation table walk or hardware update of translation table, level 1.
            syncParityOrEccErrOnMemAccessOrWalkLvl2 = 0b011110, // Synchronous parity or ECC error on memory access on translation table walk or hardware update of translation table, level 2.
            syncParityOrEccErrOnMemAccessOrWalkLvl3 = 0b011111, // Synchronous parity or ECC error on memory access on translation table walk or hardware update of translation table, level 3.
            granuleProtectionFaultOnWalkLvlN1 = 0b100011, // Granule Protection Fault on translation table walk or hardware update of translation table, level -1.
            granuleProtectionFaultOnWalkLvl0 = 0b100100, // Granule Protection Fault on translation table walk or hardware update of translation table, level 0.
            granuleProtectionFaultOnWalkLvl1 = 0b100101, // Granule Protection Fault on translation table walk or hardware update of translation table, level 1.
            granuleProtectionFaultOnWalkLvl2 = 0b100110, // Granule Protection Fault on translation table walk or hardware update of translation table, level 2.
            granuleProtectionFaultOnWalkLvl3 = 0b100111, // Granule Protection Fault on translation table walk or hardware update of translation table, level 3.
            granuleProtectionFaultNotOnWalk = 0b101000, // Granule Protection Fault, not on translation table walk or hardware update of translation table.
            addrSizeFaukltLvlN1 = 0b101001, // Address size fault, level -1.
            transFaultLvlN1 = 0b101011, // Translation fault, level -1.
            tlbConflictAbort = 0b110000, // TLB conflict abort.
            unsupportedAtomicHardwareUpdateFault = 0b110001, // Unsupported atomic hardware update fault.
        };

        pub const ExceptionClass = enum(u6) {
            trappedWF = 0b000001,
            trappedMCR = 0b000011,
            trappedMcrr = 0b000100,
            trappedMCRWithAcc = 0b000101,
            trappedLdcStcAcc = 0b000110,
            sveAsmidFpAcc = 0b000111,
            trappedLdStInst = 0b001010,
            trappedMrrcWithAcc = 0b001100,
            branchTargetExc = 0b001101,
            illegalExecState = 0b001110,
            svcInstExcAArch32 = 0b010001,
            svcInstExAArch64 = 0b010101,
            trappedMsrMrsSiAarch64 = 0b011000,
            sveFuncTrappedAcc = 0b011001,
            excFromPointerAuthInst = 0b011100,
            instAbortFromLowerExcLvl = 0b100000,
            instAbortTakenWithoutExcLvlChange = 0b100001,
            pcAlignFaultExc = 0b100010,
            dataAbortFromLowerExcLvl = 0b100100,
            dataAbortWithoutExcLvlChange = 0b100101,
            spAlignmentFaultExc = 0b100110,
            trappedFpExcAarch32 = 0b101000,
            trappedFpExcAarch64 = 0b101100,
            brkPExcFromLowerExcLvl = 0b101111,
            brkPExcWithoutExcLvlChg = 0b110001,
            softwStepExcpFromLowerExcLvl = 0b110010,
            softwStepExcTakenWithoutExcLvlChange = 0b110011,
            watchPointExcpFromALowerExcLvl = 0b110100,
            watchPointExcpWithoutTakenWithoutExcLvlChange = 0b110101,
            bkptInstExecAarch32 = 0b111000,
            bkptInstExecAarch64 = 0b111100,
        };
    };

    pub const SpsrReg = packed struct {
        pub inline fn setSpsrReg(comptime el: ExceptionLevels, val: usize) void {
            asm volatile ("msr spsr_" ++ @tagName(el) ++ ", %[val]"
                :
                : [val] "r" (val),
            );
        }
        pub inline fn readSpsrReg(comptime el: ExceptionLevels) usize {
            return asm volatile ("mrs %[curr], spsr_" ++ @tagName(el)
                : [curr] "=r" (-> usize),
            );
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
            return @as(u64, @bitCast(self));
        }

        pub inline fn setMairEl(comptime el: ExceptionLevels, val: usize) void {
            asm volatile ("msr mair_" ++ @tagName(el) ++ ", %[val]"
                :
                : [val] "r" (val),
            );
        }

        pub fn readTcrEl(comptime el: ExceptionLevels) usize {
            const x: usize = asm ("mrs %[curr], mair_" ++ @tagName(el)
                : [curr] "=r" (-> usize),
            );
            return x;
        }
    };
    pub const SctlrEl = struct {
        pub inline fn setSctlrEl(comptime el: ExceptionLevels, val: usize) void {
            asm volatile ("msr sctlr_" ++ @tagName(el) ++ ", %[val]"
                :
                : [val] "r" (val),
            );
        }

        pub fn readSctlrEl(comptime el: ExceptionLevels) usize {
            const x: usize = asm ("mrs %[curr], sctlr_" ++ @tagName(el)
                : [curr] "=r" (-> usize),
            );
            return x;
        }
    };

    // enables for el0/1 for el1
    pub inline fn enableMmu(comptime el: ExceptionLevels) void {
        // var val = SctlrEl.readSctlrEl(el);
        const val = 1 << 0;
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
            : [addr] "r" (addr),
        );
        isb();
    }

    pub inline fn branchToAddr(addr: usize) void {
        asm volatile ("br %[pc_addr]"
            :
            : [pc_addr] "r" (addr),
        );
    }

    pub fn invalidateMmuTlbEl1() void {
        // https://developer.arm.com/documentation/ddi0488/c/system-control/aarch64-register-summary/aarch64-tlb-maintenance-operations
        asm volatile ("TLBI VMALLE1IS");
    }

    pub fn setTTBR1(addr: usize) void {
        asm volatile ("msr ttbr1_el1, %[addr]"
            :
            : [addr] "r" (addr),
        );
    }

    pub fn setTTBR0(addr: usize) void {
        asm volatile ("msr ttbr0_el1, %[addr]"
            :
            : [addr] "r" (addr),
        );
    }

    pub fn readTTBR0() usize {
        return asm ("mrs %[curr], ttbr0_el1"
            : [curr] "=r" (-> usize),
        );
    }
    pub fn readTTBR1() usize {
        return asm ("mrs %[curr], ttbr1_el1"
            : [curr] "=r" (-> usize),
        );
    }

    pub fn invalidateCache() void {
        asm volatile ("IC IALLUIS");
    }
    pub fn invalidateOldPageTableEntries() void {
        const ttbr1: usize = asm ("mrs %[curr], ttbr1_el1"
            : [curr] "=r" (-> usize),
        );
        const ttbr0: usize = asm ("mrs %[curr], ttbr0_el1"
            : [curr] "=r" (-> usize),
        );

        asm volatile ("dc civac, %[addr]"
            :
            : [addr] "r" (ttbr0),
        );
        asm volatile ("dc civac, %[addr]"
            :
            : [addr] "r" (ttbr1),
        );
    }

    pub inline fn isb() void {
        asm volatile ("isb");
    }
    pub inline fn dsb() void {
        asm volatile ("dsb SY");
    }
    pub inline fn setExceptionVec(exc_vec_addr: usize) void {
        // .foramt(.{@tagName(exc_lvl)}) std.fmt.comptimePrint()
        asm volatile ("msr vbar_el1, %[exc_vec]"
            :
            : [exc_vec] "r" (exc_vec_addr),
        );

        asm volatile ("isb");
    }

    pub inline fn exceptionSvc() void {
        // Supervisor call. generates an exception targeting exception level 1 (EL1).
        asm volatile ("svc #0xdead");
    }

    pub fn getCurrentEl() usize {
        const x: usize = asm ("mrs %[curr], CurrentEL"
            : [curr] "=r" (-> usize),
        );
        return x >> 2;
    }

    pub fn getCurrentSp() usize {
        const x: usize = asm ("mov %[curr], sp"
            : [curr] "=r" (-> usize),
        );
        return x;
    }

    // ! is inlined and volatile !
    pub inline fn getCurrentPc() usize {
        return asm volatile ("adr %[pc], ."
            : [pc] "=r" (-> usize),
        );
    }

    pub inline fn setSpsel(exc_l: ExceptionLevels) void {
        asm volatile ("msr spsel, %[el]"
            :
            : [el] "r" (@intFromEnum(exc_l)),
        );
    }

    pub inline fn nop() void {
        asm volatile ("nop");
    }

    // has to happen at el3
    pub fn isSecState(el: ExceptionLevels) bool {
        if (el != .elr)
            @compileError("can only read security state in el3");
        // reading NS bit
        const x: usize = asm ("mrs %[curr], scr_el3"
            : [curr] "=r" (-> usize),
        );
        return (x & (1 << 0)) != 0;
    }

    pub fn panic() noreturn {
        while (true) {}
    }

    pub const DaifReg = packed struct(u4) {
        debug: bool,
        serr: bool,
        irqs: bool,
        fiqs: bool,

        pub fn setDaifClr(daif_config: DaifReg) void {
            asm volatile ("msr daifclr, %[conf]"
                :
                : [conf] "I" (daif_config),
            );
        }

        pub fn setDaif(daif_config: DaifReg) void {
            asm volatile ("msr daifset, %[conf]"
                :
                : [conf] "I" (daif_config),
            );
        }

        pub fn enableIrq() callconv(.C) void {
            asm volatile ("msr daifclr, %[conf]"
                :
                : [conf] "I" (DaifReg{ .debug = false, .serr = false, .irqs = true, .fiqs = false }),
            );
        }

        pub fn disableIrq() callconv(.C) void {
            asm volatile ("msr daifset, %[conf]"
                :
                : [conf] "I" (DaifReg{ .debug = false, .serr = false, .irqs = true, .fiqs = false }),
            );
        }
    };
};

comptime {
    @export(ProccessorRegMap.DaifReg.enableIrq, .{ .name = "enableIrq", .linkage = .Strong });
    @export(ProccessorRegMap.DaifReg.disableIrq, .{ .name = "disableIrq", .linkage = .Strong });
}
