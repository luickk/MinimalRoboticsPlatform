const std = @import("std");
const sysCalls = @import("userSysCallInterface.zig");
const kprint = sysCalls.SysCallPrint.kprint;

const maxProcessInQueue = 10;

pub const Semaphore = struct {
    waiting_processes: [maxProcessInQueue]usize,
    locked: std.atomic.Atomic(usize),
    pid: ?usize,
    pub fn init(s: usize) Semaphore {
        return .{
            .waiting_processes = [_]usize{0} ** maxProcessInQueue,
            .locked = std.atomic.Atomic(usize).init(s),
            .pid = null,
        };
    }

    pub fn wait(self: *Semaphore, pid: usize) void {
        kprint("CALLED\n", .{});
        self.pid = pid;
        const locked = self.locked.load(.Unordered);
        if (locked <= 0) {
            self.locked.store(locked + 1, .Unordered);
            sysCalls.haltProcess(self.pid.?);
            self.waiting_processes[locked] = self.pid.?;
        }
    }

    pub fn signal(self: *Semaphore) void {
        const locked = self.locked.load(.Unordered);
        if (locked > 0) {
            sysCalls.continueProcess(self.waiting_processes[locked]);
            self.locked.store(locked - 1, .Unordered);
        }
    }

    pub fn reset(self: *Semaphore) void {
        self.locked.store(0, .Unordered);
        self.pid = null;
    }
};
