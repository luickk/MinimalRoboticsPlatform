const std = @import("std");
const utils = @import("utils");

const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr1).kprint;

pub fn GenericTimer(comptime base_address: ?usize, comptime scheduler_freq_in_hertz: usize) type {
    _ = base_address;
    return struct {
        const Self = @This();

        pub const Error = anyerror;
        pub const timer_name = "arm_gt";

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

            const expire_count = utils.calcTicksFromHertz(cnt_freq, scheduler_freq_in_hertz);
            self.timerVal = expire_count;

            asm volatile (
                \\msr CNTP_TVAL_EL0, %[cval]
                \\mov x0, 1
                \\msr CNTP_CTL_EL0, x0
                :
                : [cval] "r" (self.timerVal),
                : "x0"
            );
        }

        pub fn timerInt(self: *Self) !void {
            asm volatile (
                \\msr CNTP_TVAL_EL0, %[cval]
                \\mov x0, 1
                \\msr CNTP_CTL_EL0, x0
                :
                : [cval] "r" (self.timerVal),
                : "x0"
            );
        }

        pub fn isEnabled(self: *Self) !bool {
            _ = self;
            const icprendr: u64 = asm ("mrs %[curr], CNTP_CTL_EL0"
                : [curr] "=r" (-> u64),
            );
            if (icprendr & (1 << 0) != 0) {
                return true;
            }
            // kprint("is pending {b} \n", .{icprendr});
            return false;
        }
    };
}
