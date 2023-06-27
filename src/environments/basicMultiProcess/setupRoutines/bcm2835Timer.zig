const std = @import("std");
const board = @import("board");
const arm = @import("arm");
const cpuContext = arm.cpuContext;

const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr1).kprint;


const sharedKernelServices = @import("sharedKernelServices");
const Scheduler = sharedKernelServices.Scheduler;

pub fn bcm2835TimerSetup(scheduler: *Scheduler) void {
	_ = scheduler;
	if (board.config.board == .raspi3b) @intToPtr(*volatile u32, board.PeriphConfig(.ttbr1).ArmGenericTimer.base_address).* = 1 << 1 | 1 << 3;
    kprint("enabled bcm2835 arm timer \n", .{});
}