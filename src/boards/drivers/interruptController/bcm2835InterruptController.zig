const std = @import("std");
const board = @import("board");
const arm = @import("arm");

const cpuContext = arm.cpuContext;

pub fn InterruptController(comptime base_address: usize) type {
    // const base_address = @import("board").PeriphConfig(addr_space).InterruptController.base_address;
    return struct {
        const Self = @This();
        pub const Error = anyerror;
        pub const RegMap = struct {
            pub const pendingBasic = @as(*volatile u32, @ptrFromInt(base_address + 0));
            pub const pendingIrq1 = @as(*volatile u32, @ptrFromInt(base_address + 0x4));
            pub const pendingIrq2 = @as(*volatile u32, @ptrFromInt(base_address + 0x8));

            pub const enableIrq1 = @as(*volatile u32, @ptrFromInt(base_address + 0x10));
            pub const enableIrq2 = @as(*volatile u32, @ptrFromInt(base_address + 0x14));
            pub const enableIrqBasic = @as(*volatile u32, @ptrFromInt(base_address + 0x18));
        };

        handler_fn: ?*const fn (cpu_context: *cpuContext.CpuContext) void,

        pub fn init() Self {
            return .{
                .handler_fn = null,
            };
        }
        pub fn initIc(self: *Self) Error!void {
            _ = self;
            // enabling all irq types
            // enalbles system timer
            RegMap.enableIrq1.* = 1 << 1;
            // RegMap.enableIrq2.* = 1 << 1;
            // RegMap.enableIrqBasic.* = 1 << 1;
        }
        pub fn addIcHandler(self: *Self, handler_fn: *const fn (cpu_context: *cpuContext.CpuContext) void) Error!void {
            self.handler_fn = handler_fn;
        }
    };
}
