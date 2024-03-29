const std = @import("std");
const alignForward = std.mem.alignForward;
const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr1).kprint;
const board = @import("board");
const utils = @import("utils");
const b_options = @import("build_options");
const arm = @import("arm");
const mmu = arm.mmu;

const KernelAlloc = @import("KernelAllocator.zig").KernelAllocator;
const Topics = @import("SysCallsTopicsInterface.zig").SysCallsTopicsInterface;
const ProccessorRegMap = arm.processor.ProccessorRegMap;
const CpuContext = arm.cpuContext.CpuContext;
const UserPageAllocator = @import("UserPageAllocator.zig").UserPageAllocator;

const app_page_table = mmu.PageTable(board.config.mem.app_vm_mem_size, board.config.mem.va_user_space_gran) catch |e| {
    @compileError(@errorName(e));
};

const kernel_page_table = mmu.PageTable(board.config.mem.app_vm_mem_size, board.config.mem.va_kernel_space_gran) catch |e| {
    @compileError(@errorName(e));
};

const log = true;

pub const Task = struct {
    pub const TaskState = enum(usize) {
        running,
        halted,
        sleeping,
        dead,
    };
    pub const PrivLevel = enum(usize) {
        // initial task that comes up after the bootloader
        boot,
        // root level user type
        kernel,
        // userspace level
        user,
    };
    pub const TaskType = enum(usize) {
        process,
        thread,
        action,
    };

    cpu_context: CpuContext,
    task_type: TaskType,
    sleep_counter: usize,
    priv_level: PrivLevel,
    state: TaskState,
    counter: isize,
    priority: isize,
    pid: ?u16,
    parent_pid: ?u16,
    child_pid: ?u16,
    preempt_count: isize,
    page_table: [app_page_table.totaPageTableSize]usize align(4096),
    app_mem: ?[]u8,
    ttbr1: ?usize,
    ttbr0: ?usize,
    pub fn init() Task {
        return Task{
            .cpu_context = CpuContext.init(),
            .task_type = .process,
            .priv_level = .user,
            .state = .dead,
            .counter = 0,
            .sleep_counter = 0,
            .pid = null,
            .parent_pid = null,
            .child_pid = null,
            .priority = 1,
            .preempt_count = 0,
            .page_table = [_]usize{0} ** app_page_table.totaPageTableSize,
            .app_mem = null,
            .ttbr1 = null,
            .ttbr0 = null,
        };
    }
};

pub const Error = error{
    PidNotFound,
    TaskIsDead,
    ForkPermissionFault,
    ThreadPermissionFault,
    CannotKillAction,
};

const maxProcesss = 10;
const maxActions = 1;
var env_processes = [_]Task{Task.init()} ** maxProcesss;

pub const Scheduler = struct {
    page_allocator: *UserPageAllocator,
    kernel_lma_offset: usize,
    scheduled_tasks: *[maxProcesss]Task,
    tasks_sleeping: [maxProcesss]?*Task,
    env_actions: [1]Task,
    current_task: *Task,
    pid_counter: u16,

    pub fn init(page_allocator: *UserPageAllocator, kernel_lma_offset: usize) Scheduler {
        return .{
            .page_allocator = page_allocator,
            .kernel_lma_offset = kernel_lma_offset,
            .tasks_sleeping = [_]?*Task{null} ** maxProcesss,
            .scheduled_tasks = &env_processes,
            .env_actions = [_]Task{Task.init()} ** 1,
            .current_task = &env_processes[0],
            .pid_counter = 0,
        };
    }

    pub fn configRootBootProcess(self: *Scheduler) void {
        // the init process contains all relevant mem&cpu context information of the "main" kernel process
        // and as such has the highest priority
        self.current_task.priority = 15;
        self.current_task.priv_level = .boot;
        self.current_task.state = .running;
        self.current_task.pid = 0;
        var app_mem: []u8 = undefined;
        app_mem.ptr = @as([*]u8, @ptrFromInt(board.config.mem.va_start));
        app_mem.len = board.config.mem.kernel_space_size;
        self.current_task.app_mem = app_mem;
        self.current_task.ttbr0 = ProccessorRegMap.readTTBR0();
        self.current_task.ttbr1 = ProccessorRegMap.readTTBR1();

        self.pid_counter += 1;
    }

    // assumes that all process counter were inited to 0
    pub fn initProcessCounter(self: *Scheduler) void {
        for (self.scheduled_tasks) |*process| {
            process.counter = (process.counter >> 1) + process.priority;
        }
    }
    pub fn schedule(self: *Scheduler, irq_context: ?*CpuContext) void {
        self.current_task.preempt_count += 1;
        errdefer self.current_task.preempt_count -= 1;
        self.current_task.counter = 0;
        // round robin for processes
        var next_proc_index: usize = 0;
        var c: isize = -1;
        while (true) {
            for (self.scheduled_tasks, 0..) |*process, i| {
                if (i >= self.pid_counter) break;
                if (process.state == .running and process.counter > c) {
                    c = process.counter;
                    next_proc_index = i;
                }
            }

            if (c != 0) break;
            for (self.scheduled_tasks, 0..) |*process, i| {
                if (i >= self.pid_counter) break;
                process.counter = (process.counter >> 1) + process.priority;
            }
        }
        self.current_task.preempt_count -= 1;
        self.switchContextToProcess(&self.scheduled_tasks[next_proc_index], irq_context);
    }

    pub fn timerIntEvent(self: *Scheduler, irq_context: *CpuContext) void {
        self.current_task.counter -= 1;
        for (self.tasks_sleeping, 0..) |proc, i| {
            if (proc) |process| {
                if (process.sleep_counter <= 0) {
                    process.state = .running;
                    self.tasks_sleeping[i] = null;
                } else {
                    process.sleep_counter -= 1;
                }
            }
        }
        if (self.current_task.counter > 0 or self.current_task.preempt_count > 0) {
            if (self.current_task.counter <= 0) kprint("self.current_task.preempt_count: {d} \n", .{self.current_task.preempt_count});
            if (log) kprint("--------- PROC WAIT counter: {d} \n", .{self.current_task.counter});
            // return all the way back to the exc vector table where cpu state is restored from the stack
            // if the task is dead already, we don't return back to the process but schedule the next task
            if (self.current_task.state == .running) return;
        }
        self.schedule(irq_context);
    }
    pub fn initAppsInScheduler(self: *Scheduler, apps: []const []const u8, topics_mem_pool: []u8) !void {
        self.current_task.preempt_count += 1;
        defer self.current_task.preempt_count -= 1;

        for (apps, 0..) |app, j| {
            const i = j + 1;
            // skip root task (index 0)
            const req_pages = try std.math.divCeil(usize, board.config.mem.app_vm_mem_size, board.config.mem.va_user_space_gran.page_size);
            const app_mem = try self.page_allocator.allocNPage(req_pages);

            std.mem.copy(u8, app_mem, app);
            self.scheduled_tasks[i].cpu_context.elr_el1 = 0;
            self.scheduled_tasks[i].cpu_context.sp_el0 = alignForward(usize, app.len + board.config.mem.app_stack_size, 16);
            self.scheduled_tasks[i].cpu_context.x0 = self.pid_counter;
            self.scheduled_tasks[i].app_mem = app_mem;
            self.scheduled_tasks[i].priority = self.current_task.priority;
            self.scheduled_tasks[i].state = .running;
            self.scheduled_tasks[i].priv_level = .user;
            self.scheduled_tasks[i].counter = self.scheduled_tasks[i].priority;
            self.scheduled_tasks[i].preempt_count = 0;
            self.scheduled_tasks[i].pid = self.pid_counter;

            // initing the apps page-table
            {
                // MMU page dir config
                var page_table_write = try app_page_table.init(&self.scheduled_tasks[i].page_table, self.kernel_lma_offset);
                const user_space_mapping = mmu.Mapping{
                    .mem_size = board.config.mem.app_vm_mem_size,
                    .pointing_addr_start = self.kernel_lma_offset + board.config.mem.kernel_space_size + @intFromPtr(app_mem.ptr),
                    .virt_addr_start = 0,
                    .granule = board.boardConfig.Granule.Fourk,
                    .addr_space = .ttbr0,
                    .flags_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .read_write, .attrIndex = .mair0 },
                    .flags_non_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .read_write },
                };
                try page_table_write.mapMem(user_space_mapping);
            }

            // initing the apps topics-interface
            {
                // MMU page dir config
                var page_table_write = try app_page_table.init(&self.scheduled_tasks[i].page_table, self.kernel_lma_offset);
                const topics_interace_mapping = mmu.Mapping{
                    .mem_size = topics_mem_pool.len,
                    .pointing_addr_start = self.kernel_lma_offset + board.config.mem.kernel_space_size + @intFromPtr(topics_mem_pool.ptr),
                    .virt_addr_start = 0x20000000,
                    .granule = board.boardConfig.Granule.Fourk,
                    .addr_space = .ttbr0,
                    .flags_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .read_write, .attrIndex = .mair0 },
                    .flags_non_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .read_write },
                };
                try page_table_write.mapMem(topics_interace_mapping);
            }
            self.scheduled_tasks[i].ttbr0 = self.kernel_lma_offset + utils.toTtbr0(usize, @intFromPtr(&self.scheduled_tasks[i].page_table));
            self.pid_counter += 1;
        }
    }

    pub fn killTask(self: *Scheduler, pid: u16) !void {
        self.current_task.preempt_count += 1;
        errdefer self.current_task.preempt_count -= 1;
        _ = try self.checkForPid(pid);
        const pid_info = try self.findTaskByPid(pid);
        if (pid_info.task_type == .action) return Error.CannotKillAction;
        self.scheduled_tasks[pid_info.index].state = .dead;
        for (self.scheduled_tasks) |*proc| {
            if (proc.task_type == .thread and proc.parent_pid == pid) {
                proc.state = .dead;
            }
        }
        self.current_task.preempt_count -= 1;
        self.schedule(null);
    }

    pub fn exitTask(self: *Scheduler) !noreturn {
        try self.killTaskAndChildrend(self.current_task.pid.?);
        while (true) {}
    }

    // function is deprecated since new tasks cannot be created without allocating new memory which is not legal in system runtime
    // todo => find way around policy
    pub fn deepForkProcess(self: *Scheduler, to_clone_pid: u16) !void {
        self.current_task.preempt_count += 1;
        defer {
            self.current_task.preempt_count -= 1;
            self.switchMemContext(self.current_task.ttbr0.?, null);
        }

        // switching to boot userspace page table (which spans all apps in order to acces other apps memory with their relative userspace addresses...)
        self.switchMemContext(self.scheduled_tasks[0].ttbr0.?, null);

        try self.checkForPid(to_clone_pid);
        if (self.scheduled_tasks[to_clone_pid].priv_level == .boot) return Error.ForkPermissionFault;

        const req_pages = try std.math.divCeil(usize, board.config.mem.app_vm_mem_size, board.config.mem.va_user_space_gran.page_size);
        const new_app_mem = try self.page_allocator.allocNPage(req_pages);

        const new_pid: u16 = self.pid_counter;

        std.mem.copy(u8, new_app_mem, self.scheduled_tasks[to_clone_pid].app_mem.?);
        self.scheduled_tasks[new_pid] = self.scheduled_tasks[to_clone_pid];
        self.scheduled_tasks[new_pid].app_mem = new_app_mem;
        self.scheduled_tasks[new_pid].ttbr0 = self.kernel_lma_offset + utils.toTtbr0(usize, @intFromPtr(&self.scheduled_tasks[new_pid].page_table));
        self.scheduled_tasks[new_pid].pid = new_pid;
        self.scheduled_tasks[new_pid].parent_pid = to_clone_pid;
        self.scheduled_tasks[to_clone_pid].child_pid = new_pid;
        self.pid_counter += 1;

        for (&self.scheduled_tasks) |*proc| {
            if (proc.task_type == .thread or proc.parent_pid == to_clone_pid) {
                try self.cloneThread(proc.pid.?, new_pid);
            }
        }
    }

    pub fn cloneThread(self: *Scheduler, to_clone_thread_pid: usize, new_proc_pid: usize) !void {
        self.current_task.preempt_count += 1;
        defer self.current_task.preempt_count -= 1;
        try self.checkForPid(to_clone_thread_pid);
        if (!self.scheduled_tasks[to_clone_thread_pid].task_type == .thread) return;

        const new_pid = self.pid_counter;
        self.scheduled_tasks[new_pid] = self.scheduled_tasks[to_clone_thread_pid];
        self.scheduled_tasks[new_pid].pid = new_pid;
        self.scheduled_tasks[new_pid].parent_pid = new_proc_pid;
        self.scheduled_tasks[new_pid].ttbr0 = self.scheduled_tasks[new_proc_pid].ttbr0;
        self.scheduled_tasks[new_pid].ttbr1 = self.scheduled_tasks[new_proc_pid].ttbr1;

        self.pid_counter += 1;
    }
    pub fn createThreadFromCurrentProcess(self: *Scheduler, entry_fn_ptr: *const anyopaque, thread_fn_ptr: *const anyopaque, thread_stack_addr: usize, args: *anyopaque) !void {
        self.current_task.preempt_count += 1;
        defer self.current_task.preempt_count -= 1;
        const curr_task_index = (try self.findTaskByPid(self.current_task.pid.?)).index;
        const new_pid: u16 = self.pid_counter;
        self.scheduled_tasks[new_pid].pid = new_pid;
        self.scheduled_tasks[new_pid].task_type = .thread;
        self.scheduled_tasks[new_pid].state = self.scheduled_tasks[curr_task_index].state;
        self.scheduled_tasks[new_pid].counter = self.scheduled_tasks[curr_task_index].priority;
        self.scheduled_tasks[new_pid].priority = self.scheduled_tasks[curr_task_index].priority;
        self.scheduled_tasks[new_pid].parent_pid = self.current_task.pid.?;
        self.scheduled_tasks[new_pid].cpu_context.x0 = @intFromPtr(thread_fn_ptr);
        self.scheduled_tasks[new_pid].cpu_context.x1 = @intFromPtr(args);
        self.scheduled_tasks[new_pid].cpu_context.elr_el1 = @intFromPtr(entry_fn_ptr);
        self.scheduled_tasks[new_pid].cpu_context.sp_el0 = thread_stack_addr;
        self.scheduled_tasks[new_pid].cpu_context.sp_el1 = thread_stack_addr;
        self.scheduled_tasks[new_pid].priv_level = self.scheduled_tasks[curr_task_index].priv_level;
        self.scheduled_tasks[new_pid].ttbr0 = self.scheduled_tasks[curr_task_index].ttbr0;
        self.scheduled_tasks[new_pid].ttbr1 = self.scheduled_tasks[curr_task_index].ttbr1;
        self.pid_counter += 1;
    }

    // provides a generic entry function (generic in regard to the thread and argument function since @call builtin needs them to properly invoke the thread start)
    pub fn KernelThreadInstance(comptime thread_fn: anytype, comptime Args: type) type {
        const ThreadFn = @TypeOf(thread_fn);
        return struct {
            pub fn threadEntry(entry_fn: *ThreadFn, entry_args: *Args) callconv(.C) void {
                @call(.auto, entry_fn, entry_args.*);
            }
        };
    }
    // creates thread for current process
    // info: use only permitted at kernel boot/init
    pub fn createKernelThread(self: *Scheduler, app_alloc: *KernelAlloc, thread_fn: anytype, args: anytype) !void {
        const thread_stack_mem = try app_alloc.alloc(u8, board.config.mem.k_stack_size, 16);
        var thread_stack_start: []u8 = undefined;
        thread_stack_start.ptr = @as([*]u8, @ptrFromInt(@intFromPtr(thread_stack_mem.ptr) + thread_stack_mem.len));
        thread_stack_start.len = thread_stack_mem.len;

        var arg_mem: []const u8 = undefined;
        arg_mem.ptr = @as([*]const u8, @ptrCast(@alignCast(&args)));
        arg_mem.len = @sizeOf(@TypeOf(args));

        std.mem.copy(u8, thread_stack_start, arg_mem);

        const entry_fn = &(KernelThreadInstance(thread_fn, @TypeOf(args)).threadEntry);
        const thread_fn_ptr = &thread_fn;

        const thread_stack_addr = @intFromPtr(thread_stack_start.ptr) - alignForward(usize, @sizeOf(@TypeOf(args)), 16);
        const args_ptr = thread_stack_start.ptr;
        try self.createThreadFromCurrentProcess(@as(*const anyopaque, @ptrCast(entry_fn)), @as(*const anyopaque, @ptrCast(thread_fn_ptr)), thread_stack_addr, @as(*anyopaque, @ptrCast(args_ptr)));
    }
    pub fn ActionInstance(comptime thread_fn: anytype) type {
        const ThreadFn = @TypeOf(thread_fn);
        return struct {
            pub fn actionEntry(entry_fn: *ThreadFn) callconv(.C) void {
                @call(.auto, entry_fn, .{});
            }
        };
    }

    pub fn initActionsInScheduler(self: *Scheduler, loading_actions: []const []const u8, topics_mem_pool: []u8) !void {
        // kprint("ss: {any} \n", .{loading_actions});
        self.current_task.preempt_count += 1;
        defer self.current_task.preempt_count -= 1;
        for (loading_actions, 0..) |action, i| {
            const req_pages = try std.math.divCeil(usize, board.config.mem.app_vm_mem_size, board.config.mem.va_user_space_gran.page_size);
            const app_mem = try self.page_allocator.allocNPage(req_pages);

            std.mem.copy(u8, app_mem, action);
            self.env_actions[i].cpu_context.elr_el1 = 0;
            self.env_actions[i].cpu_context.sp_el0 = alignForward(usize, action.len + board.config.mem.app_stack_size, 16);
            self.env_actions[i].cpu_context.x0 = self.pid_counter;
            self.env_actions[i].task_type = .action;
            self.env_actions[i].app_mem = app_mem;
            self.env_actions[i].priority = self.current_task.priority;
            self.env_actions[i].state = .halted;
            self.env_actions[i].priv_level = .user;
            self.env_actions[i].counter = self.env_actions[i].priority;
            self.env_actions[i].preempt_count = 0;
            self.env_actions[i].pid = self.pid_counter;

            // initing the apps page-table
            {
                // MMU page dir config
                var page_table_write = try app_page_table.init(&self.env_actions[i].page_table, self.kernel_lma_offset);
                const user_space_mapping = mmu.Mapping{
                    .mem_size = board.config.mem.app_vm_mem_size,
                    .pointing_addr_start = self.kernel_lma_offset + board.config.mem.kernel_space_size + @intFromPtr(app_mem.ptr),
                    .virt_addr_start = 0,
                    .granule = board.boardConfig.Granule.Fourk,
                    .addr_space = .ttbr0,
                    .flags_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .read_write, .attrIndex = .mair0 },
                    .flags_non_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .read_write },
                };
                try page_table_write.mapMem(user_space_mapping);
            }

            // initing the apps topics-interface
            {
                // MMU page dir config
                var page_table_write = try app_page_table.init(&self.env_actions[i].page_table, self.kernel_lma_offset);
                const topics_interace_mapping = mmu.Mapping{
                    .mem_size = topics_mem_pool.len,
                    .pointing_addr_start = self.kernel_lma_offset + board.config.mem.kernel_space_size + @intFromPtr(topics_mem_pool.ptr),
                    .virt_addr_start = 0x20000000,
                    .granule = board.boardConfig.Granule.Fourk,
                    .addr_space = .ttbr0,
                    .flags_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .read_write, .attrIndex = .mair0 },
                    .flags_non_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .read_write },
                };
                try page_table_write.mapMem(topics_interace_mapping);
            }
            self.env_actions[i].ttbr0 = self.kernel_lma_offset + utils.toTtbr0(usize, @intFromPtr(&self.env_actions[i].page_table));
            self.pid_counter += 1;
        }
    }

    pub fn killTaskAndChildrend(self: *Scheduler, starting_pid: u16) !void {
        self.current_task.preempt_count += 1;
        errdefer self.current_task.preempt_count -= 1;
        const index = try self.checkForPid(starting_pid);
        self.scheduled_tasks[index].state = .dead;
        var child_proc_index: ?u16 = index;
        while (child_proc_index != null) {
            self.scheduled_tasks[child_proc_index.?].state = .dead;
            for (self.scheduled_tasks) |*proc| {
                if (proc.task_type == .thread and proc.parent_pid == child_proc_index.?) {
                    proc.state = .dead;
                }
            }
            if (self.scheduled_tasks[child_proc_index.?].child_pid) |child_pid| {
                child_proc_index = (try self.findTaskByPid(child_pid)).index;
            } else child_proc_index = null;
        }
        self.current_task.preempt_count -= 1;
        self.schedule(null);
    }

    pub fn getCurrentProcessPid(self: *Scheduler) u16 {
        return self.current_task.pid.?;
    }

    pub fn setProcessState(self: *Scheduler, pid: u16, state: Task.TaskState, irq_context: ?*CpuContext) !void {
        const index = (try self.findTaskByPid(pid)).index;
        self.scheduled_tasks[index].state = state;
        if (pid == self.current_task.pid and irq_context != null) self.schedule(irq_context.?);
    }

    pub fn setProcessAsleep(self: *Scheduler, pid: u16, cycles_sleeping: usize, irq_context: *CpuContext) !void {
        const index = try self.checkForPid(pid);
        for (self.tasks_sleeping, 0..) |proc, i| {
            if (proc == null) {
                self.tasks_sleeping[i] = &self.scheduled_tasks[index];
            }
        }
        self.scheduled_tasks[index].sleep_counter = cycles_sleeping;
        self.scheduled_tasks[index].state = .sleeping;
        self.schedule(irq_context);
    }

    fn checkForPid(self: *Scheduler, pid: u16) !u16 {
        const index = (try self.findTaskByPid(pid)).index;
        if (self.scheduled_tasks[index].state == .dead) return Error.TaskIsDead;
        return index;
    }

    // args (process pointers) are past via registers
    fn switchContextToProcess(self: *Scheduler, next_process: *Task, irq_context: ?*CpuContext) void {
        const prev_process = self.current_task;
        self.current_task = next_process;

        if (next_process.priv_level == .user) self.switchMemContext(next_process.ttbr0, null);

        switchCpuContext(self, prev_process, next_process, irq_context);
    }

    fn switchCpuPrivLvl(priv_level: Task.PrivLevel) void {
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

    // irq_context is optional in case the previous scheduled task is not needed anymore
    fn switchCpuContext(self: *Scheduler, from: *Task, to: *Task, irq_context: ?*CpuContext) void {
        kprint("current_procc: {*}, self.current_task.preempt_count: {d} \n", .{ self.current_task, self.current_task.preempt_count });
        if (log) {
            kprint("from: ({s}, {s}, {*}) to ({s}, {s}, {*}) \n", .{ @tagName(from.priv_level), @tagName(from.state), from, @tagName(to.priv_level), @tagName(to.state), to });
            kprint("current scheduled_tasks(n={d}): \n", .{self.pid_counter + 1});
            for (self.scheduled_tasks, 0..) |*proc, i| {
                if (i >= self.pid_counter) break;
                kprint("pid: {d} {s}, {s}, {s}, {any}, {*}\n", .{ i, @tagName(proc.priv_level), @tagName(proc.priv_level), @tagName(proc.state), proc.*.task_type, proc });
            }
        }
        if (irq_context) |context| from.cpu_context = context.*;
        switchCpuPrivLvl(to.priv_level);
        // restore Context and erets
        asm volatile (
            \\ mov sp, %[sp_addr]
            \\ b _restoreContextFromSp
            :
            : [sp_addr] "r" (&to.cpu_context),
        );
    }

    pub fn switchMemContext(self: *Scheduler, ttbr_0_addr: ?usize, ttbr_1_addr: ?usize) void {
        _ = self;
        if (ttbr_0_addr) |addr| ProccessorRegMap.setTTBR0(addr);
        if (ttbr_1_addr) |addr| ProccessorRegMap.setTTBR1(addr);
        if (ttbr_0_addr != null or ttbr_0_addr != null) {
            asm volatile ("tlbi vmalle1is");
            // ensure completion of TLB invalidation
            asm volatile ("dsb ish");
            asm volatile ("isb");
        }
    }

    fn findTaskByPid(self: *Scheduler, pid: u16) !struct { index: u16, task_type: Task.TaskType } {
        for (self.scheduled_tasks, 0..) |*proc, i| {
            if (proc.pid == pid) return .{ .index = @as(u16, @truncate(i)), .task_type = .process };
        }
        for (&self.env_actions, 0..) |*action, i| {
            if (action.pid == pid) return .{ .index = @as(u16, @truncate(i)), .task_type = .action };
        }
        return Error.PidNotFound;
    }
};
