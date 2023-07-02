const std = @import("std");
const sysCalls = @import("userSysCallInterface.zig");
const kprint = sysCalls.SysCallPrint.kprint;

// todo => make configurable and throw error if exceeded
const maxProcessInQueue = 10;

pub const Semaphore = struct {
    waiting_processes: [maxProcessInQueue]?usize,
    i: isize,
    locked_tasks_index: usize,
    pub fn init(s: isize) Semaphore {
        return .{
            .waiting_processes = [_]?usize{0} ** maxProcessInQueue,
            .locked_tasks_index = 0,
            .i = s,
        };
    }
    pub fn wait(self: *Semaphore, pid: ?usize) void {
        var to_halt_proc: usize = undefined;
        if (pid == null) to_halt_proc = sysCalls.getPid() else to_halt_proc = pid.?;
        if (self.i < 1) {
            kprint("HALTING {d} \n", .{self.i});
            self.locked_tasks_index += 1;
            self.waiting_processes[self.locked_tasks_index] = to_halt_proc;
            sysCalls.haltProcess(to_halt_proc);
        }
        self.i -= 1;
    }

    pub fn signal(self: *Semaphore) void {
        if (self.i < 1) {
            if (self.waiting_processes[self.locked_tasks_index]) |locked_pid| {
                self.locked_tasks_index -= 1;
                sysCalls.continueProcess(locked_pid);
            }   
            self.i += 1;
        }   
    }
};
