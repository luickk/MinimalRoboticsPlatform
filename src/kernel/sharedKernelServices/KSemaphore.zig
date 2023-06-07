const std = @import("std");
pub const Scheduler = @import("Scheduler.zig").Scheduler;
const arm = @import("arm");
const CpuContext = arm.cpuContext.CpuContext;
const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr1).kprint;

const maxProcessInQueue = 10;

pub const Semaphore = struct {
    waiting_processes: [maxProcessInQueue]?usize,
    locked: usize,
    pub fn init(s: usize) Semaphore {
        return .{
            .waiting_processes = [_]?usize{0} ** maxProcessInQueue,
            .locked = s,
        };
    }
    pub fn wait(self: *Semaphore, pid: usize, scheduler: *Scheduler, irq_context: *CpuContext) void {
        self.locked += 1;
        kprint("LOCKED {d} at {d} \n", .{ pid, self.locked });
        self.waiting_processes[self.locked] = pid;
        kprint("--- \n", .{});
        scheduler.setProcessState(pid, .halted, irq_context);
    }

    pub fn signal(self: *Semaphore, scheduler: *Scheduler) void {
        if (self.waiting_processes[self.locked]) |locked_pid| {
            self.locked -= 1;
            scheduler.setProcessState(locked_pid, .running, null);
        }
    }
};
