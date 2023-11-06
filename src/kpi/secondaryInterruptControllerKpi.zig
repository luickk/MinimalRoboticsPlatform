const std = @import("std");
const arm = @import("arm");

const cpuContext = arm.cpuContext;

pub fn SecondaryInterruptControllerKpi(
    comptime Context: type,
    comptime IcError: type,
    comptime initIcDriver_: fn (context: Context) IcError!void,
    comptime addIcHandler_: fn (context: Context, handler_fn: *const fn (cpu_context: *cpuContext.CpuContext) void) IcError!void,
    comptime RegMap_: type,
) type {
    return struct {
        const Self = @This();
        pub const Error = IcError;
        pub const RegMap = RegMap_;

        context: Context,

        pub fn init(context: Context) Self {
            return .{
                .context = context,
            };
        }

        pub fn initIcDriver(self: Self) Error!void {
            try initIcDriver_(self.context);
        }

        pub fn addIcHandler(self: Self, handler_fn: *const fn (cpu_context: *cpuContext.CpuContext) void) Error!void {
            try addIcHandler_(self.context, handler_fn);
        }
    };
}
