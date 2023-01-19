const std = @import("std");
const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr1).kprint;
const board = @import("board");
const utils = @import("utils");
const b_options = @import("build_options");
const arm = @import("arm");
const mmu = arm.mmu;
const ProccessorRegMap = arm.processor.ProccessorRegMap;
const CpuContext = arm.cpuContext.CpuContext;
const UserPageAllocator = @import("UserPageAllocator.zig").UserPageAllocator;

const bl_bin_size = 0x2000000;

const app_page_table = mmu.PageTable(board.config.mem.app_vm_mem_size, board.boardConfig.Granule.FourkSection) catch |e| {
    @compileError(@errorName(e));
};

pub const Process = struct {
    pub const ProcessState = enum(usize) {
        running,
        halted,
        done,
    };
    pub const ProcessType = enum(usize) {
        boot,
        kernel,
        user,
    };
    cpu_context: CpuContext,
    proc_type: ProcessType,
    state: ProcessState,
    counter: isize,
    priority: isize,
    preempt_count: isize,
    page_table: [app_page_table.totaPageTableSize]usize align(4096),

    pub fn init() Process {
        return Process{
            .cpu_context = CpuContext.init(),
            .proc_type = .user,
            .state = .running,
            .counter = 0,
            .priority = 1,
            .preempt_count = 1,
            .page_table = [_]usize{0} ** app_page_table.totaPageTableSize,
        };
    }
    pub fn setPreempt(self: *Process, state: bool) void {
        if (state) self.preempt_count -= 1;
        if (!state) self.preempt_count += 1;
    }
};

pub const Error = error{
    PidNotFound,
};
const maxProcesss = 10;

// globals

var processs = [_]Process{Process.init()} ** maxProcesss;
var current_process: *Process = &processs[0];

var pid_counter: usize = 0;

pub const Scheduler = struct {
    page_allocator: *UserPageAllocator,
    kernel_lma_offset: usize,

    pub fn init(page_allocator: *UserPageAllocator, kernel_lma_offset: usize) Scheduler {
        return Scheduler{
            .page_allocator = page_allocator,
            .kernel_lma_offset = kernel_lma_offset,
        };
    }

    pub fn setUpSchedulerStartConf(self: *Scheduler) void {
        _ = self;
        // the init process contains all relevant mem&cpu context information of the "main" kernel process
        // and as such has the highest priority
        current_process.priority = 15;
        current_process.proc_type = .boot;
        pid_counter += 1;
    }

    // assumes that all process counter were inited to 0
    pub fn initProcessCounter(self: *Scheduler) void {
        _ = self;
        for (processs) |*process| {
            process.counter = (process.counter >> 1) + process.priority;
        }
    }
    pub fn schedule(self: *Scheduler, irq_context: *CpuContext) void {
        // current_process.counter -= 1;
        // if (current_process.counter > 0 or current_process.preempt_count > 0) return;
        current_process.counter = 0;

        current_process.setPreempt(false);
        var next: usize = 0;
        var c: isize = -1;
        while (true) {
            for (processs) |*process, i| {
                if (i >= pid_counter) break;
                // kprint("process {d}: {any} \n", .{ i, process.* });
                if (process.state == .running and process.counter > c) {
                    c = process.counter;
                    next = i;
                }
            }

            if (c != 0) break;
            for (processs) |*process, i| {
                if (i >= pid_counter) break;
                process.counter = (process.counter >> 1) + process.priority;
            }
        }
        self.switchContextToProcess(&processs[next], irq_context);
        current_process.setPreempt(true);
    }

    pub fn timerIntEvent(self: *Scheduler, irq_context: *CpuContext) void {
        current_process.counter -= 1;
        if (current_process.counter > 0 and current_process.preempt_count > 0) {
            kprint("--------- WAIT WAIT pc: {x} \n", .{ProccessorRegMap.getCurrentPc()});
            // return all the way back to the exc vector table where cpu state is restored from the stack
            // if the task is done already, we don't return back to the process but schedule the next task
            if (current_process.state != .done)
                return;
        }
        current_process.counter = 0;

        ProccessorRegMap.DaifReg.enableIrq();
        self.schedule(irq_context);
        ProccessorRegMap.DaifReg.disableIrq();
    }

    pub fn initAppsInScheduler(self: *Scheduler, apps: []const []const u8) !void {
        current_process.setPreempt(false);
        for (apps) |app| {
            const req_pages = try std.math.divCeil(usize, board.config.mem.app_vm_mem_size, self.page_allocator.granule.page_size);
            var app_mem = try self.page_allocator.allocNPage(req_pages);

            var pid = pid_counter;

            std.mem.copy(u8, app_mem, app);
            processs[pid].cpu_context.elr_el1 = 0;
            processs[pid].cpu_context.sp_el0 = try utils.ceilRoundToMultiple(app.len + board.config.mem.app_stack_size, 16);
            processs[pid].cpu_context.x0 = pid;

            // initing the apps page-table
            {
                // MMU page dir config
                var page_table_write = try app_page_table.init(&processs[pid].page_table, self.kernel_lma_offset);

                const user_space_mapping = mmu.Mapping{
                    .mem_size = board.config.mem.app_vm_mem_size,
                    .pointing_addr_start = self.kernel_lma_offset + board.config.mem.kernel_space_size + @ptrToInt(app_mem.ptr),
                    .virt_addr_start = 0,
                    .granule = board.boardConfig.Granule.FourkSection,
                    .addr_space = .ttbr0,
                    .flags_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .read_write, .attrIndex = .mair0 },
                    .flags_non_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .read_write },
                };
                try page_table_write.mapMem(user_space_mapping);
            }

            processs[pid].priority = current_process.priority;
            processs[pid].state = .running;
            processs[pid].proc_type = .user;
            processs[pid].counter = processs[pid].priority;
            processs[pid].preempt_count = 1;

            pid_counter += 1;
        }
        current_process.setPreempt(true);
    }

    pub fn killTask(self: *Scheduler, pid: usize) !void {
        _ = self;
        try checkForPid(pid);
        processs[pid].state = .done;
    }

    // todo => optionally implement check for pid's process state
    fn checkForPid(pid: usize) !void {
        if (pid > maxProcesss) return Error.PidNotFound;
    }

    // args (process pointers) are past via registers
    fn switchContextToProcess(self: *Scheduler, next_process: *Process, irq_context: *CpuContext) void {
        var prev_process = current_process;
        current_process = next_process;

        {
            var ttbr0_addr: usize = 0;
            switch (next_process.proc_type) {
                .user => ttbr0_addr = self.kernel_lma_offset + mmu.toTtbr0(usize, @ptrToInt(&next_process.page_table)),
                .boot, .kernel => ttbr0_addr = ProccessorRegMap.readTTBR0(),
            }
            switchMemContext(ttbr0_addr);
        }

        switchCpuContext(prev_process, next_process, irq_context);
    }

    fn switchCpuState(next_process: *Process) void {
        switch (next_process.proc_type) {
            .user => {
                ProccessorRegMap.SpsrReg.setSpsrReg(.el1, ProccessorRegMap.SpsrReg.readSpsrReg(.el1) & (~@as(usize, 0b0111)));
                ProccessorRegMap.setSpsel(.el1);
            },
            .kernel, .boot => {
                ProccessorRegMap.SpsrReg.setSpsrReg(.el1, ProccessorRegMap.SpsrReg.readSpsrReg(.el1) | 0b0101);
                ProccessorRegMap.setSpsel(.el0);
            },
        }
    }

    fn switchCpuContext(from: *Process, to: *Process, irq_context: *CpuContext) void {
        kprint("from: ({s}, {s}, {*}) to ({s}, {s}, {*}) \n", .{ @tagName(from.proc_type), @tagName(from.state), from, @tagName(to.proc_type), @tagName(to.state), to });
        kprint("page table: {*} \n", .{&to.page_table});

        kprint("pc: {x} \n", .{ProccessorRegMap.getCurrentPc()});
        from.cpu_context = irq_context.*;
        switchCpuState(to);
        // restore Context and erets
        asm volatile (
            \\ mov sp, %[sp_addr]
            \\ b _restoreContextFromSp
            :
            : [sp_addr] "r" (&to.cpu_context),
        );
    }

    fn switchMemContext(ttbr_0_addr: usize) void {
        ProccessorRegMap.setTTBR0(ttbr_0_addr);
        asm volatile ("tlbi vmalle1is");
        // ensure completion of TLB invalidation
        asm volatile ("dsb ish");
        asm volatile ("isb");
    }
};
