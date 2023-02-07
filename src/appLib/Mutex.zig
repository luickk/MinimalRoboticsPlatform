const std = @import("std");
const sysCalls = @import("userSysCallInterface.zig");
const kprint = sysCalls.SysCallPrint.kprint;

const maxProcessInQueue = 10;

pub const Mutex = struct {
    waiting_processes: [maxProcessInQueue]usize,
    last_waiting_proc_index: usize,
    locked: std.atomic.Atomic(bool),

    pub fn init() Mutex {
        return .{
            .waiting_processes = [_]usize{0} ** maxProcessInQueue,
            .last_waiting_proc_index = 0,
            .locked = std.atomic.Atomic(bool).init(false),
        };
    }

    pub fn lock(self: *Mutex) void {
        if (self.locked.load(.Unordered)) {
            const my_pid = sysCalls.getPid();
            sysCalls.haltProcess(my_pid);
            self.waiting_processes[self.last_waiting_proc_index] = my_pid;
            self.last_waiting_proc_index += 1;
        }
        self.locked.store(true, .Unordered);
        kprint("lock: {any} \n", .{self.locked.load(.Unordered)});
    }

    pub fn unlock(self: *Mutex) void {
        if (self.locked.load(.Unordered) and self.last_waiting_proc_index >= 1) {
            sysCalls.continueProcess(self.waiting_processes[self.last_waiting_proc_index]);
            self.last_waiting_proc_index -= 1;
        }
        self.locked.store(false, .Unordered);
        kprint("unlock: {any}", .{self.locked.load(.Unordered)});
    }
};
