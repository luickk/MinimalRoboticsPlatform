const board = @import("board");
const std = @import("std");
const sharedKernelServices = @import("sharedKernelServices");
const Scheduler = sharedKernelServices.Scheduler;

const raspi3bSetup = @import("raspi3bSetup.zig").bcm2835Setup;
const qemuVirtSetup = @import("qemuVirtSetup.zig").qemuVirtSetup;

const SetupRoutine = fn (scheduler: *Scheduler) void;

const boardSpecificSetup = blk: {
    if (std.mem.eql(u8, board.config.board_name, "raspi3b")) {
        break :blk [_]SetupRoutine{raspi3bSetup};
    } else if (std.mem.eql(u8, board.config.board_name, "qemuVirt")) {
        break :blk [_]SetupRoutine{qemuVirtSetup};
    }
};

// setupRoutines array is loaded and inited by the kernel
pub const setupRoutines = [_]SetupRoutine{} ++ boardSpecificSetup;
