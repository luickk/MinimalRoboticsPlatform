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

const app_page_table = mmu.PageTable(board.config.mem.app_vm_mem_size, board.boardConfig.Granule.Fourk) catch |e| {
    @compileError(@errorName(e));
};

pub const Process = struct {
    pub const ProcessState = enum(usize) {
        running,
        halted,
        done,
    };
    pub const PrivLevel = enum(usize) {
        // initial task that comes up after the bootloader
        boot,
        // root level user type
        kernel,
        // userspace level
        user,
    };

    cpu_context: CpuContext,
    priv_level: PrivLevel,
    state: ProcessState,
    counter: isize,
    priority: isize,
    pid: ?usize,
    parent_pid: ?usize,
    child_pid: ?usize,
    preempt_count: isize,
    page_table: [app_page_table.totaPageTableSize]usize align(4096),
    app_mem: ?[]u8,
    ttbr1: ?usize,
    ttbr0: ?usize,
    pub fn init() Process {
        return Process{
            .cpu_context = CpuContext.init(),
            .priv_level = .user,
            .state = .running,
            .counter = 0,
            .pid = null,
            .parent_pid = null,
            .child_pid = null,
            .priority = 1,
            .preempt_count = 1,
            .page_table = [_]usize{0} ** app_page_table.totaPageTableSize,
            .app_mem = null,
            .ttbr1 = null,
            .ttbr0 = null,
        };
    }
    pub fn setPreempt(self: *Process, state: bool) void {
        if (state) self.preempt_count -= 1;
        if (!state) self.preempt_count += 1;
    }
};

pub const Error = error{
    PidNotFound,
    ForkPermissionFault,
};
const maxProcesss = 10;

// globals

var processses = [_]Process{Process.init()} ** maxProcesss;
var current_process: *Process = &processses[0];

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

    pub fn configRootBootProcess(self: *Scheduler) void {
        _ = self;
        // the init process contains all relevant mem&cpu context information of the "main" kernel process
        // and as such has the highest priority
        current_process.priority = 15;
        current_process.priv_level = .boot;
        current_process.state = .running;
        current_process.pid = 0;
        var app_mem: []u8 = undefined;
        app_mem.ptr = @intToPtr([*]u8, board.config.mem.va_start);
        app_mem.len = board.config.mem.kernel_space_size;
        current_process.app_mem = app_mem;
        current_process.ttbr0 = ProccessorRegMap.readTTBR0();
        current_process.ttbr1 = ProccessorRegMap.readTTBR1();

        pid_counter += 1;
    }

    // assumes that all process counter were inited to 0
    pub fn initProcessCounter(self: *Scheduler) void {
        _ = self;
        for (processses) |*process| {
            process.counter = (process.counter >> 1) + process.priority;
        }
    }
    pub fn schedule(self: *Scheduler, irq_context: *CpuContext) void {
        current_process.setPreempt(false);
        current_process.counter = 0;
        // round robin for processes
        var next_proc_pid: usize = 0;
        var c: isize = -1;
        while (true) {
            for (processses) |*process, i| {
                if (i >= pid_counter) break;
                if (process.state == .running and process.counter > c) {
                    c = process.counter;
                    next_proc_pid = i;
                }
            }

            if (c != 0) break;
            for (processses) |*process, i| {
                if (i >= pid_counter) break;
                process.counter = (process.counter >> 1) + process.priority;
            }
        }
        current_process.setPreempt(true);
        self.switchContextToProcess(&processses[next_proc_pid], irq_context);
    }

    pub fn timerIntEvent(self: *Scheduler, irq_context: *CpuContext) void {
        current_process.counter -= 1;
        if (current_process.counter > 0 and current_process.preempt_count > 0) {
            kprint("--------- PROC WAIT pc: {x} \n", .{irq_context.elr_el1});
            // return all the way back to the exc vector table where cpu state is restored from the stack
            // if the task is done already, we don't return back to the process but schedule the next task
            if (current_process.state != .done) return;
        }
        self.schedule(irq_context);
    }
    pub fn initAppsInScheduler(self: *Scheduler, apps: []const []const u8) !void {
        current_process.setPreempt(false);
        for (apps) |app| {
            const req_pages = try std.math.divCeil(usize, board.config.mem.app_vm_mem_size, self.page_allocator.granule.page_size);
            const app_mem = try self.page_allocator.allocNPage(req_pages);

            var pid = pid_counter;

            std.mem.copy(u8, app_mem, app);
            processses[pid].cpu_context.elr_el1 = 0;
            processses[pid].cpu_context.sp_el0 = try utils.ceilRoundToMultiple(app.len + board.config.mem.app_stack_size, 16);
            processses[pid].cpu_context.x0 = pid;
            processses[pid].app_mem = app_mem;
            processses[pid].priority = current_process.priority;
            processses[pid].state = .running;
            processses[pid].priv_level = .user;
            processses[pid].counter = processses[pid].priority;
            processses[pid].preempt_count = 1;
            processses[pid].pid = pid;

            // initing the apps page-table
            {
                // MMU page dir config
                var page_table_write = try app_page_table.init(&processses[pid].page_table, self.kernel_lma_offset);
                const user_space_mapping = mmu.Mapping{
                    .mem_size = board.config.mem.app_vm_mem_size,
                    .pointing_addr_start = self.kernel_lma_offset + board.config.mem.kernel_space_size + @ptrToInt(app_mem.ptr),
                    .virt_addr_start = 0,
                    .granule = board.boardConfig.Granule.Fourk,
                    .addr_space = .ttbr0,
                    .flags_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .read_write, .attrIndex = .mair0 },
                    .flags_non_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .read_write },
                };
                try page_table_write.mapMem(user_space_mapping);
            }
            processses[pid].ttbr0 = self.kernel_lma_offset + utils.toTtbr0(usize, @ptrToInt(&processses[pid].page_table));
            pid_counter += 1;
        }
        current_process.setPreempt(true);
    }

    pub fn killProcess(self: *Scheduler, pid: usize) !void {
        _ = self;
        current_process.setPreempt(false);
        try checkForPid(pid);
        processses[pid].state = .done;
        current_process.setPreempt(true);
    }

    pub fn deepForkProcess(self: *Scheduler, to_clone_pid: usize) !void {
        current_process.setPreempt(false);
        // switching to boot userspace page table (which spans all apps in order to acces other apps memory with their relative userspace addresses...)
        switchMemContext(processses[0].ttbr0.?, null);
        try checkForPid(to_clone_pid);
        if (processses[to_clone_pid].priv_level == .boot) return Error.ForkPermissionFault;

        const req_pages = try std.math.divCeil(usize, board.config.mem.app_vm_mem_size, self.page_allocator.granule.page_size);
        var new_app_mem = try self.page_allocator.allocNPage(req_pages);

        var new_pid = pid_counter;

        std.mem.copy(u8, new_app_mem, processses[to_clone_pid].app_mem.?);
        processses[new_pid] = processses[to_clone_pid];
        processses[new_pid].app_mem = new_app_mem;
        processses[new_pid].ttbr0 = self.kernel_lma_offset + utils.toTtbr0(usize, @ptrToInt(&processses[new_pid].page_table));
        processses[new_pid].pid = new_pid;
        processses[new_pid].parent_pid = to_clone_pid;
        processses[to_clone_pid].child_pid = new_pid;

        pid_counter += 1;
        switchMemContext(current_process.ttbr0.?, null);
        current_process.setPreempt(true);
    }
    pub fn createThreadFromCurrentProcess(self: *Scheduler, thread_fn_ptr: *const fn () void, thread_stack_addr: usize) void {
        _ = self;
        current_process.setPreempt(false);
        var new_pid = pid_counter;
        processses[new_pid].pid = new_pid;
        processses[new_pid].counter = processses[current_process.pid.?].priority;
        processses[new_pid].priority = processses[current_process.pid.?].priority;
        processses[new_pid].cpu_context.elr_el1 = @ptrToInt(thread_fn_ptr);
        processses[new_pid].cpu_context.sp = thread_stack_addr;
        processses[new_pid].priv_level = processses[current_process.pid.?].priv_level;
        processses[new_pid].ttbr0 = processses[current_process.pid.?].ttbr0;
        processses[new_pid].ttbr1 = processses[current_process.pid.?].ttbr1;
        pid_counter += 1;
        current_process.setPreempt(true);
    }

    pub fn killProcessAndChildrend(self: *Scheduler, starting_pid: usize) !void {
        _ = self;
        current_process.setPreempt(false);
        try checkForPid(starting_pid);
        processses[starting_pid].state = .done;
        var child_proc_pid = processses[starting_pid].child_pid;
        while (child_proc_pid != null) {
            processses[child_proc_pid.?].state = .done;
            child_proc_pid = processses[child_proc_pid.?].child_pid;
        }
        current_process.setPreempt(true);
    }

    pub fn getCurrentProcessPid(self: *Scheduler) usize {
        _ = self;
        return current_process.pid.?;
    }

    // todo => optionally implement check for pid's process state
    fn checkForPid(pid: usize) !void {
        if (pid > maxProcesss) return Error.PidNotFound;
    }

    // args (process pointers) are past via registers
    fn switchContextToProcess(self: *Scheduler, next_process: *Process, irq_context: *CpuContext) void {
        _ = self;
        var prev_process = current_process;
        current_process = next_process;

        switch (next_process.priv_level) {
            // .ttbr1 is an optional and null for user type processes
            .user => switchMemContext(next_process.ttbr0, next_process.ttbr1),
            .boot, .kernel => switchMemContext(next_process.ttbr0, next_process.ttbr1),
        }

        switchCpuContext(prev_process, next_process, irq_context);
    }

    fn switchCpuPrivLvl(priv_level: Process.PrivLevel) void {
        switch (priv_level) {
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
        kprint("from: ({s}, {s}, {*}) to ({s}, {s}, {*}) \n", .{ @tagName(from.priv_level), @tagName(from.state), from, @tagName(to.priv_level), @tagName(to.state), to });
        kprint("current processses(n={d}): \n", .{pid_counter + 1});
        for (processses) |*proc, i| {
            if (i >= pid_counter) break;
            kprint("pid: {d} {s}, {s}, {s} \n", .{ i, @tagName(proc.priv_level), @tagName(proc.priv_level), @tagName(proc.state) });
        }
        from.cpu_context = irq_context.*;
        switchCpuPrivLvl(to.priv_level);
        // restore Context and erets
        asm volatile (
            \\ mov sp, %[sp_addr]
            \\ b _restoreContextFromSp
            :
            : [sp_addr] "r" (&to.cpu_context),
        );
    }

    fn switchMemContext(ttbr_0_addr: ?usize, ttbr_1_addr: ?usize) void {
        if (ttbr_0_addr) |addr| ProccessorRegMap.setTTBR0(addr);
        if (ttbr_1_addr) |addr| ProccessorRegMap.setTTBR1(addr);
        if (ttbr_0_addr != null or ttbr_0_addr != null) {
            asm volatile ("tlbi vmalle1is");
            // ensure completion of TLB invalidation
            asm volatile ("dsb ish");
            asm volatile ("isb");
        }
    }
};
