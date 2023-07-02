const std = @import("std");
const Scheduler = @import("Scheduler.zig").Scheduler;
const arm = @import("arm");
const CpuContext = arm.cpuContext.CpuContext;
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
    pub fn wait(self: *Semaphore, pid: usize, scheduler: *Scheduler, irq_context: *CpuContext) void {
        self.i -= 1;
        if (self.i < 1) {
            self.locked_tasks_index += 1;
            self.waiting_processes[self.locked_tasks_index] = pid;
        scheduler.setProcessState(pid, .halted, irq_context);
        }
    }

    pub fn signal(self: *Semaphore, scheduler: *Scheduler) void {
        if (self.i < 1) {
            if (self.waiting_processes[self.locked_tasks_index]) |locked_pid| {
                self.i += 1;
                self.locked_tasks_index -= 1;
                scheduler.setProcessState(locked_pid, .running, null);
            }   
        }
        
    }
};
