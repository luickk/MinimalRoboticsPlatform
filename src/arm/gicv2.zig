const std = @import("std");
const arm = @import("arm");
const mmu = @import("mmu.zig");
const AddrSpace = @import("board").boardConfig.AddrSpace;

const kprint = @import("periph").uart.UartWriter(.ttbr1).kprint;

// identifiers for the vector table addr_handler call
pub const ExceptionType = enum(u64) {
    el1Sync = 0x1,
    el1Irq = 0x2,
    el1Fiq = 0x3,
    el1Err = 0x4,
    elxSpx = 0x5,
};

export const el1Sync = ExceptionType.el1Sync;
export const el1Err = ExceptionType.el1Err;
export const el1Fiq = ExceptionType.el1Fiq;
export const el1Irq = ExceptionType.el1Irq;
export const elxSpx = ExceptionType.elxSpx;

// reads interrupt data placed by exc. vec from the stack
pub const ExceptionFrame = struct {
    regs: [30]u64,
    int_type: u64,
    esr_el1: u64,
    lr: u64,
};

pub fn Gic(comptime addr_space: AddrSpace) type {
    const gicCfg = @import("board").PeriphConfig(addr_space).GicV2;
    return struct {
        // initialize gic controller
        pub fn init() !void {
            Gicc.init();
            try Gicd.init();
        }

        // 8.8 The GIC Distributor register map
        pub const GicdRegMap = struct {
            pub const gicdBase = gicCfg.base_address; // gicd mmio base address

            // Enables interrupts and affinity routing
            pub const ctlr = @intToPtr(*volatile u32, gicdBase + 0x0);
            // Deactivates the corresponding interrupt. These registers are used when saving and restoring GIC state.
            pub const intType = @intToPtr(*volatile u32, gicdBase + 0x004);
            // distributor implementer identification register
            pub const iidr = @intToPtr(*volatile u32, gicdBase + 0x008);
            // Controls whether the corresponding interrupt is in Group 0 or Group 1.
            pub const igroupr = @intToPtr(*volatile u32, gicdBase + 0x080);
            // interrupt set-enable registers
            pub const isenabler = @intToPtr(*volatile u32, gicdBase + 0x100);
            // Disables forwarding of the corresponding interrupt to the CPU interfaces.
            pub const icenabler = @intToPtr(*volatile u32, gicdBase + 0x180);
            // interrupt set-pending registers
            pub const ispendr = @intToPtr(*volatile u32, gicdBase + 0x200);
            // Removes the pending state from the corresponding interrupt.
            pub const icpendr = @intToPtr(*volatile u32, gicdBase + 0x280);
            pub const isactiver = @intToPtr(*volatile u32, gicdBase + 0x300);
            // Deactivates the corresponding interrupt. These registers are used when saving and restoring GIC state.
            pub const icactiver = @intToPtr(*volatile u32, gicdBase + 0x380);
            //  interrupt priority registers
            pub const ipriorityr = @intToPtr(*volatile u32, gicdBase + 0x400);
            // interrupt processor targets registers
            pub const itargetsr = @intToPtr(*volatile u32, gicdBase + 0x800);
            // Determines whether the corresponding interrupt is edge-triggered or level-sensitive
            pub const icfgr = @intToPtr(*volatile u32, gicdBase + 0xc00);
            // software generated interrupt register
            pub const nscar = @intToPtr(*volatile u32, gicdBase + 0xe00);
            // sgi clear-pending registers
            pub const cpendsgir = @intToPtr(*volatile u32, gicdBase + 0xf10);
            // sgi set-pending registers
            pub const spendsgir = @intToPtr(*volatile u32, gicdBase + 0xf20);
            pub const sgir = @intToPtr(*volatile u32, 0xf00);
        };

        // 8.12 the gic cpu interface register map
        pub const GiccRegMap = struct {
            pub const giccBase = gicCfg.base_address + 0x10000; // gicc mmio base address

            // cpu interface control register
            pub const ctlr = @intToPtr(*volatile u32, giccBase + 0x000);
            // interrupt priority mask register
            pub const pmr = @intToPtr(*volatile u32, giccBase + 0x004);
            // binary point register
            pub const bpr = @intToPtr(*volatile u32, giccBase + 0x008);
            // interrupt acknowledge register
            pub const iar = @intToPtr(*volatile u32, giccBase + 0x00c);
            // end of interrupt register
            pub const eoir = @intToPtr(*volatile u32, giccBase + 0x010);
            // running priority register
            pub const rpr = @intToPtr(*volatile u32, giccBase + 0x014);
            // highest pending interrupt register
            pub const hpir = @intToPtr(*volatile u32, giccBase + 0x018);
            // aliased binary point register
            pub const abpr = @intToPtr(*volatile u32, giccBase + 0x01c);
            // cpu interface identification register
            pub const iidr = @intToPtr(*volatile u32, giccBase + 0x0fc);
        };

        pub const GicdRegValues = struct {
            // gicd...
            pub const itargetsrPerReg = 4;
            pub const itargetsrSizePerReg = 8;
            pub const icfgrPerReg = 16;
            pub const icfgrSizePerReg = 2;
            pub const intPerReg = 32; // 32 interrupts per reg
            pub const ipriorityPerReg = 4; // 4 priority per reg
            pub const iprioritySizePerReg = 8; // priority element size
            pub const itargetsrCore0TargetBmap = 0x01010101; // cpu interface 0

            // 8.9.4 gicd_ctlr, distributor control register
            pub const gicdCtlrEnable = 0x1; // enable gicd
            pub const gicdCtlrDisable = 0; // disable gicd

            // 8.9.7 gicd_icfgr<n>, interrupt configuration registers
            pub const gicdIcfgrLevel = 0; // level-sensitive
            pub const gicdIcfgrEdge = 0x2; // edge-triggered
        };

        pub const GiccRegValues = struct {
            // gicc..
            // 8.13.14 gicc_pmr, cpu interface priority mask register
            pub const giccPmrPrioMin = 0xff; // the lowest level mask
            pub const giccPmrPrioHigh = 0x0; // the highest level mask
            // 8.13.7 gicc_ctlr, cpu interface control register
            pub const giccCtlrEnable = 0x1; // enable gicc
            pub const giccCtlrDisable = 0x0; // disable gicc
            // 8.13.6 gicc_bpr, cpu interface binary point register
            // in systems that support only one security state, when gicc_ctlr.cbpr == 0,  this register determines only group 0 interrupt preemption.
            pub const giccBprNoGroup = 0x0; // handle all interrupts
            // 8.13.11 gicc_iar, cpu interface interrupt acknowledge register
            pub const giccIarIntrIdmask = 0x3ff; // 0-9 bits means interrupt id
            pub const giccIarSpuriousIntr = 0x3ff; // 1023 means spurious interrupt
        };

        pub const InterruptIds = enum(u32) {
            non_secure_physical_timer = 30,
        };

        pub const Gicc = struct {
            // initialize gic controller
            fn init() void {
                // disable cpu interface
                GiccRegMap.ctlr.* = GiccRegValues.giccCtlrDisable;

                // set the priority level as the lowest priority
                // note: higher priority corresponds to a lower priority field value in the gic_pmr.
                // in addition to this, writing 255 to the gicc_pmr always sets it to the largest supported priority field value.
                GiccRegMap.pmr.* = GiccRegValues.giccPmrPrioMin;

                // handle all of interrupts in a single group
                GiccRegMap.bpr.* = GiccRegValues.giccBprNoGroup;

                // clear all of the active interrupts
                var pending_irq: u32 = 0;
                while (pending_irq != GiccRegValues.giccIarSpuriousIntr) : (pending_irq = GiccRegMap.iar.* & GiccRegValues.giccIarSpuriousIntr) {
                    GiccRegMap.eoir.* = GiccRegMap.iar.*;
                }

                // enable cpu interface
                GiccRegMap.ctlr.* = GiccRegValues.giccCtlrEnable;
            }

            // send end of interrupt to irq line for gic
            // ctrlr   irq controller Configrmation
            // irq     irq number
            pub fn gicv2Eoi(irq: u32) void {
                Gicd.gicdClearPending(irq);
            }

            // find pending irq
            // irqp an irq number to be processed
            pub fn gicv2FindPendingIrq() ![gicCfg.intMax]u32 {
                var ret_array = [_]u32{0} ** gicCfg.intMax;
                var i: u32 = 0;
                var i_found: u32 = 0;
                while (gicCfg.intMax > i) : (i += 1) {
                    if (try Gicd.gicdProbePending(i)) {
                        ret_array[i_found] = i;
                        i_found += 1;
                    }
                }
                return ret_array;
            }
        };

        pub const Gicd = struct {
            // init the gic distributor
            fn init() !void {
                var i: u32 = 0;
                var irq_num: u32 = 0;

                // diable distributor
                GicdRegMap.ctlr.* = GiccRegValues.giccCtlrDisable;
                // disable all irqs & clear pending
                irq_num = try std.math.divExact(u32, gicCfg.intMax + GicdRegValues.intPerReg, GicdRegValues.intPerReg);
                while (irq_num > i) : (i += 1) {
                    @intToPtr(*volatile u32, @ptrToInt(GicdRegMap.icenabler) + 4 * i).* = ~@as(u32, 0);
                    @intToPtr(*volatile u32, @ptrToInt(GicdRegMap.icpendr) + 4 * i).* = ~@as(u32, 0);
                }
                i = 0;

                // set all of interrupt priorities as the lowest priority
                irq_num = try std.math.divExact(u32, gicCfg.intMax + GicdRegValues.ipriorityPerReg, GicdRegValues.ipriorityPerReg);
                while (irq_num > i) : (i += 1) {
                    @intToPtr(*volatile u32, @ptrToInt(GicdRegMap.ipriorityr) + 4 * i).* = ~@as(u32, 0);
                }
                i = 0;

                // set target of all of shared arm to processor 0
                i = try std.math.divExact(u32, gicCfg.intNoSpi0, GicdRegValues.itargetsrPerReg);
                while ((try std.math.divExact(u32, gicCfg.intMax + GicdRegValues.itargetsrPerReg, GicdRegValues.itargetsrPerReg)) > i) : (i += 1) {
                    @intToPtr(*volatile u32, @ptrToInt(GicdRegMap.itargetsr) + 4 * i).* = @as(u32, GicdRegValues.itargetsrCore0TargetBmap);
                }

                // set trigger type for all armeral interrupts level triggered
                i = try std.math.divExact(u32, gicCfg.intNoPpi0, GicdRegValues.icfgrPerReg);
                while ((try std.math.divExact(u32, gicCfg.intMax + GicdRegValues.icfgrPerReg, GicdRegValues.icfgrPerReg)) > i) : (i += 1) {
                    @intToPtr(*volatile u32, @ptrToInt(GicdRegMap.icfgr) + 4 * i).* = GicdRegValues.gicdIcfgrLevel;
                }

                // enable distributor
                GicdRegMap.ctlr.* = GicdRegValues.gicdCtlrEnable;
            }

            pub fn gicdEnableInt(irq_id: InterruptIds) !void {
                const clear_ena_bit = @truncate(u5, try std.math.mod(u32, @enumToInt(irq_id), @as(u32, 32)));
                const reg = calcReg(GicdRegMap.isenabler, @enumToInt(irq_id));
                reg.* = reg.* | (@as(u32, 1) << clear_ena_bit);
            }

            pub fn gicdDisableInt(irq_id: InterruptIds) !void {
                // irq_id mod 32
                const clear_ena_bit = @truncate(u5, try std.math.mod(u32, @enumToInt(irq_id), @as(u32, 32)));
                const reg = calcReg(GicdRegMap.icenabler, @enumToInt(irq_id));
                reg.* = reg.* << clear_ena_bit;
            }

            fn gicdClearPending(irq_id: InterruptIds) !void {
                // irq_id mod 32
                const clear_ena_bit = @truncate(u5, try std.math.mod(u32, @enumToInt(irq_id), @as(u32, 32)));
                const reg = calcReg(GicdRegMap.icpendr, @enumToInt(irq_id));
                reg.* = reg.* << clear_ena_bit;
            }

            pub fn gicdProbePending(irq_id: u32) !bool {
                // irq_id mod 32
                const clear_ena_ind = @truncate(u5, try std.math.mod(u32, irq_id, @as(u32, 32)));

                const cleared_ena_bit = @as(u32, 1) << clear_ena_ind;

                const is_pending = calcReg(GicdRegMap.icpendr, irq_id).* & cleared_ena_bit;
                return is_pending != 0;
            }

            // from the gicv2 docs:
            // For interrupt ID m, when DIV and MOD are the integer division and modulo operations:
            // • the corresponding GICD_ICENABLERn number, n, is given by m = n DIV 32
            // • the offset of the required GICD_ICENABLERn is (0x180 + (4*n))
            // • the bit number of the required Clear-enable bit in this register is m MOD 32.
            //
            // according to the arm docs in order to calc the correct dma reg to access, the irq id has to be divided by 32,
            // whereby a non exact division is **not possible**, a solution is to cast the resulting float to an int.
            //
            // there is few occasions on which bit shifts are more explicit and less confusing, but this is defenitely one of them.
            // in order to prevent that (int to float) conversion/ casting chaos, all operations below are done with bitshifts
            // For some reason arm docs describe them mathematically which is a huge footgun if realised that way
            fn calcReg(addr_start: *volatile u32, irq_id: u32) *volatile u32 {
                // wtf... but that's what the docs say.... and it works -.-
                // const reg = @ptrToInt(GicdRegMap.isenabler) + 4 * (@floatToInt(usize, (try std.math.divFloor(f32, @intToFloat(f32, irq_id), @as(u32, 32)))));

                // alternative version:
                // irq_id (div by 32) * 4
                var reg = (irq_id >> @as(u32, 5)) << 2;

                return @intToPtr(*volatile u32, @ptrToInt(addr_start) + reg);
            }

            // set an interrupt target processor
            // irq irq number
            // p   target processor mask
            // 0x1 processor 0
            // 0x2 processor 1
            // 0x4 processor 2
            // 0x8 processor 3
            pub fn gicdSetTarget(irq_id: InterruptIds, p: u32) !void {
                const reg = @intToPtr(*volatile u32, @ptrToInt(GicdRegMap.itargetsr) + (@enumToInt(irq_id) & ~@as(u32, 0x3)));
                var targets: u32 = reg.*;
                const shift = @truncate(u5, (@enumToInt(irq_id) % 4) * 8);
                targets &= ~(@as(u32, 0xff) << shift);
                targets |= p << shift;

                reg.* = targets;
            }

            // set an interrupt priority
            // irq  irq number
            // prio interrupt priority in arm specific expression
            pub fn gicdSetPriority(irq_id: InterruptIds, prio: u8) void {
                @intToPtr(*volatile u8, @ptrToInt(GicdRegMap.ipriorityr) + @enumToInt(irq_id) * 8).* = prio;
            }

            // configure irq
            // irq     irq number
            // config  configuration value for gicd_icfgr
            pub fn gicdConfig(irq_id: InterruptIds, config: u32) void {
                var shift: u5 = @truncate(u5, (@enumToInt(irq_id) % GicdRegValues.icfgrPerReg) * GicdRegValues.icfgrSizePerReg); // gicd_icfgr has 16 fields, each field has 2bits.

                var reg: u32 = @intToPtr(*volatile u32, @ptrToInt(GicdRegMap.icfgr) + ((@enumToInt(irq_id) / GicdRegValues.icfgrPerReg) * 4)).*;

                reg &= ~((@as(u32, 0x03)) << shift); // clear the field
                reg |= ((@as(u32, config)) << shift); // set the value to the field correponding to irq
                @intToPtr(*volatile u32, @ptrToInt(GicdRegMap.icfgr) + ((@enumToInt(irq_id) / GicdRegValues.icfgrPerReg) * 4)).* = reg;
            }
        };
    };
}
