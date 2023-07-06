const std = @import("std");
const board = @import("board");
const sysCalls = @import("userSysCallInterface.zig");
const kprint = sysCalls.SysCallPrint.kprint;

pub const Mutex = struct {
    const Error = error {
        OutOfStaticMem,
    };

    waiting_processes: [board.config.static_memory_reserves.mutex_max_process_in_queue]u16,
    last_waiting_proc_index: usize,
    curr_lock_owner_pid: usize,
    locked: std.atomic.Atomic(bool),

    pub fn init() Mutex {
        return .{
            .waiting_processes = [_]u16{0} ** board.config.static_memory_reserves.mutex_max_process_in_queue,
            .last_waiting_proc_index = 0,
            .curr_lock_owner_pid = 0,
            .locked = std.atomic.Atomic(bool).init(false),
        };
    }

    pub fn lock(self: *Mutex) !void {
        sysCalls.increaseCurrTaskPreemptCounter();
        const my_pid = sysCalls.getPid();
        if (self.locked.load(.Unordered)) {
            if (self.last_waiting_proc_index > self.waiting_processes.len) return Error.OutOfStaticMem;
            sysCalls.haltProcess(my_pid);
            self.waiting_processes[self.last_waiting_proc_index] = my_pid;
            self.last_waiting_proc_index += 1;
        }
        self.curr_lock_owner_pid = my_pid;
        self.locked.store(true, .Unordered);
    }

    pub fn unlock(self: *Mutex) void {
        if (self.locked.load(.Unordered) and self.last_waiting_proc_index > 0 and self.curr_lock_owner_pid == sysCalls.getPid()) {
            sysCalls.continueProcess(self.waiting_processes[self.last_waiting_proc_index]);
            self.curr_lock_owner_pid = self.waiting_processes[self.last_waiting_proc_index];
            self.last_waiting_proc_index -= 1;
        }
        self.locked.store(false, .Unordered);
        sysCalls.decreaseCurrTaskPreemptCounter();
    }
};
