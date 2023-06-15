const std = @import("std");
const sysCalls = @import("userSysCallInterface.zig");
const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr1).kprint;

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
    pub fn wait(self: *Semaphore, pid: usize) void {
        self.i -= 1;
        if (self.i < 0) {
            self.locked_tasks_index += 1;
            self.waiting_processes[self.locked_tasks_index] = pid;
            sysCalls.haltProcess(pid);
        }
    }

    pub fn signal(self: *Semaphore) void {
        if (self.i < 0) {
            if (self.waiting_processes[self.locked_tasks_index]) |locked_pid| {
                self.i += 1;
                self.locked_tasks_index -= 1;
                sysCalls.continueProcess(locked_pid);
            }   
        }
        
    }
};
