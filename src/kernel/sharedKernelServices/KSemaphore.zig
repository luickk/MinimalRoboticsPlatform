const std = @import("std");
const board = @import("board");
const Scheduler = @import("Scheduler.zig").Scheduler;
const arm = @import("arm");
const CpuContext = arm.cpuContext.CpuContext;
const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr1).kprint;

pub fn Semaphore(comptime max_process_waiting: ?usize) type {
    const max_process_waiting_queue = max_process_waiting orelse board.config.static_memory_reserves.ksemaphore_max_process_in_queue;
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
        pub fn wait(self: *Self, pid: u16, scheduler: *Scheduler, irq_context: *CpuContext) !void {
            self.i -= 1;
            if (self.i < 1) {
                self.locked_tasks_index += 1;
                if (self.locked_tasks_index > self.waiting_processes.len) return Error.OutOfStaticMem;
                self.waiting_processes[self.locked_tasks_index] = pid;
                scheduler.setProcessState(pid, .halted, irq_context);
            }
        }

        pub fn signal(self: *Self, scheduler: *Scheduler) void {
            if (self.i < 1) {
                if (self.waiting_processes[self.locked_tasks_index]) |locked_pid| {
                    self.i += 1;
                    self.locked_tasks_index -= 1;
                    scheduler.setProcessState(locked_pid, .running, null);
                }   
            }
            
        }
    };
}
