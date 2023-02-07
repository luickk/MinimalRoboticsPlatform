const std = @import("std");
const sysCalls = @import("userSysCallInterface.zig");
const kprint = sysCalls.SysCallPrint.kprint;

const maxProcessInQueue = 10;

pub const Semaphore = struct {
    waiting_processes: [maxProcessInQueue]usize,
    locked: std.atomic.Atomic(usize),
    pub fn init() Semaphore {
        return .{
            .waiting_processes = [_]usize{0} ** maxProcessInQueue,
            .locked = std.atomic.Atomic(usize).init(0),
        };
    }

    pub fn lock(self: *Semaphore) void {
        const locked = self.locked.load(.Unordered);
        if (locked > 0) {
            const my_pid = sysCalls.getPid();
            sysCalls.haltProcess(my_pid);
            self.waiting_processes[locked] = my_pid;
        }
        self.locked.store(locked + 1, .Unordered);
    }
    pub fn unlock(self: *Semaphore) void {
        const locked = self.locked.load(.Unordered);
        if (locked > 0) {
            sysCalls.continueProcess(self.waiting_processes[locked]);
            self.locked.store(locked - 1, .Unordered);
        }
    }
};
