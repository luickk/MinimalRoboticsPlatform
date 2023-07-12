const std = @import("std");
const board = @import("board");
const sysCalls = @import("userSysCallInterface.zig");
const kprint = sysCalls.SysCallPrint.kprint;

// max_process_waiting defines how many processes can be put into the waiting queue
pub fn Semaphore(comptime max_process_waiting: ?usize) type {
    const max_process_waiting_queue = max_process_waiting orelse board.config.static_memory_reserves.semaphore_max_process_in_queue;
    return struct {
        const Self = @This();
        const Error = error {
            OutOfStaticMem,
        };

        waiting_processes: [max_process_waiting_queue]?u16,
        i: isize,
        locked_tasks_index: u16,
        pub fn init(s: isize) Self {
            return .{
                .waiting_processes = [_]?u16{0} ** max_process_waiting_queue,
                .locked_tasks_index = 0,
                .i = s,
            };
        }
        pub fn wait(self: *Self, pid: ?u16) !void {
            var to_halt_proc: u16 = undefined;
            if (pid == null) to_halt_proc = (try sysCalls.getPid()) else to_halt_proc = pid.?;
            if (self.i < 1) {
                self.locked_tasks_index += 1;
                if (self.locked_tasks_index > self.waiting_processes.len) return Error.OutOfStaticMem;
                self.waiting_processes[self.locked_tasks_index] = to_halt_proc;
                try sysCalls.haltProcess(to_halt_proc);
            }
            self.i -= 1;
        }

        pub fn signal(self: *Self) !void {
            if (self.i < 1) {
                if (self.waiting_processes[self.locked_tasks_index]) |locked_pid| {
                    self.locked_tasks_index -= 1;
                    try sysCalls.continueProcess(locked_pid);
                }   
                self.i += 1;
            }   
        }
    };
}
