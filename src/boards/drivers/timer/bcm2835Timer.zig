const utils = @import("utils");
const std = @import("std");

pub fn Bcm2835Timer(comptime base_address: ?usize, comptime scheduler_freq_in_hertz: usize) type {
    return struct {
        const Self = @This();

        pub const Error = anyerror;
        pub const timer_name = "bcm2835_timer";

        // raspberry 3b available timers: system timer (this one), arm timer, free runnning timer
        // raspberry system timer frequency is 1 Mhz
        var cnt_freq: u32 = 1000000;

        var increasePerTick: u32 = 0;

        pub const RegMap = struct {
            pub const timerCs = @as(*volatile u32, @ptrFromInt(base_address.? + 0x0));
            pub const timerLo = @as(*volatile u32, @ptrFromInt(base_address.? + 0x4));
            pub const timerHi = @as(*volatile u32, @ptrFromInt(base_address.? + 0x8));
            pub const timerC0 = @as(*volatile u32, @ptrFromInt(base_address.? + 0xc));
            pub const timerC1 = @as(*volatile u32, @ptrFromInt(base_address.? + 0x10));
            pub const timerClo = @as(*volatile u32, @ptrFromInt(base_address.? + 0x4));
        };

        // address values
        pub const RegValues = struct {
            // System Timer Controll State irq clear vals
            pub const timerCsM0: u32 = 1 << 0;
            pub const timerCsM1: u32 = 1 << 1;
            pub const timerCsM2: u32 = 1 << 2;
            pub const timerCsM3: u32 = 1 << 3;
        };

        timerVal: u32,
        initialTimerHi: u32,

        pub fn init() Self {
            return .{
                .timerVal = 0,
                .initialTimerHi = 0,
            };
        }

        pub fn initTimer(self: *Self) Error!void {
            self.initialTimerHi = RegMap.timerHi.*;
            self.timerVal = RegMap.timerLo.*;
            increasePerTick = @as(u32, @truncate(utils.calcTicksFromHertz(cnt_freq, scheduler_freq_in_hertz)));
            self.timerVal += increasePerTick;
            RegMap.timerC1.* = self.timerVal;
        }

        // the qemu system timer is weird. It only triggers an interrupt if timerC1 is == timerLo instead of timerC1 is <= timerLo.
        // Qemu devs stated that this is intended and what the documentation is saying, but are also doubting that this is the physical bcm2835 implementation
        // more on that issue here: https://gitlab.com/qemu-project/qemu/-/issues/1651
        // also I'm unsure how overflows are handled since it's not described in the docs properly
        pub fn handleTimerIrq(self: *Self) Error!void {
            self.timerVal = RegMap.timerLo.* + increasePerTick;
            if (self.initialTimerHi != RegMap.timerHi.*) {
                self.timerVal = RegMap.timerLo.*;
                self.timerVal += increasePerTick;
                self.initialTimerHi = RegMap.timerHi.*;
            }

            RegMap.timerC1.* = self.timerVal;
            RegMap.timerCs.* = RegMap.timerCs.* | RegValues.timerCsM1;
        }

        pub fn isEnabled(self: *Self) !bool {
            _ = self;
            if (RegMap.timerCs.* & RegValues.timerCsM1 != 0) {
                return true;
            }
            return false;
        }
    };
}
