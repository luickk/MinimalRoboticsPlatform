const std = @import("std");
const utils = @import("utils");

// const periph = @import("periph");
// const kprint = periph.uart.UartWriter(.ttbr1).kprint;

pub fn GenericTimer(comptime base_address: ?usize, comptime scheduler_freq_in_hertz: usize) type {
    _ = base_address;
    return struct {
        const Self = @This();

        pub const Error = anyerror;

        timerVal: usize,

        pub fn init() Self {
            return .{
                .timerVal = 0,
            };
        }

        pub fn getFreq() usize {
            return asm ("mrs %[curr], CNTFRQ_EL0"
                : [curr] "=r" (-> usize),
            );
        }

        // initialize gic controller
        pub fn setupGt(self: *Self) !void {
            const cnt_freq = getFreq();

            const increasePerTick = try utils.calcTicksFromHertz(cnt_freq, scheduler_freq_in_hertz);

            self.timerVal += increasePerTick;
            asm volatile (
                \\msr CNTP_TVAL_EL0, %[cval]
                \\mov x0, 1
                \\msr cntp_ctl_el0, x0
                :
                : [cval] "r" (self.timerVal),
                : "x0"
            );
        }

        pub fn timerInt(self: *Self) !void {
            asm volatile (
                \\msr CNTP_TVAL_EL0, %[cval]
                \\mov x0, 1
                \\msr cntp_ctl_el0, x0
                :
                : [cval] "r" (self.timerVal),
                : "x0"
            );
        }
    };
}
