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

pub const Process = struct {
    pub const ProcessState = enum(usize) {
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

    cpu_context: CpuContext,
    is_thread: bool,
    sleep_counter: usize,
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
            .is_thread = false,
            .priv_level = .user,
            .state = .running,
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
};

const maxProcesss = 10;
var processses = [_]Process{Process.init()} ** maxProcesss;

pub const Scheduler = struct {
    page_allocator: *UserPageAllocator,
    kernel_lma_offset: usize,
    processses: *[maxProcesss]Process,
    processses_sleeping: [maxProcesss]?*Process,
    current_process: *Process,
    pid_counter: usize,

    pub fn init(page_allocator: *UserPageAllocator, kernel_lma_offset: usize) Scheduler {
        return .{
            .page_allocator = page_allocator,
            .kernel_lma_offset = kernel_lma_offset,
            .processses_sleeping = [_]?*Process{null} ** maxProcesss,
            .processses = &processses,
            .current_process = &processses[0],
            .pid_counter = 0,
        };
    }

    pub fn configRootBootProcess(self: *Scheduler) void {
        // the init process contains all relevant mem&cpu context information of the "main" kernel process
        // and as such has the highest priority
        self.current_process.priority = 15;
        self.current_process.priv_level = .boot;
        self.current_process.state = .running;
        self.current_process.pid = 0;
        var app_mem: []u8 = undefined;
        app_mem.ptr = @intToPtr([*]u8, board.config.mem.va_start);
        app_mem.len = board.config.mem.kernel_space_size;
        self.current_process.app_mem = app_mem;
        self.current_process.ttbr0 = ProccessorRegMap.readTTBR0();
        self.current_process.ttbr1 = ProccessorRegMap.readTTBR1();

        self.pid_counter += 1;
    }

    // assumes that all process counter were inited to 0
    pub fn initProcessCounter(self: *Scheduler) void {
        for (self.processses) |*process| {
            process.counter = (process.counter >> 1) + process.priority;
        }
    }
    pub fn schedule(self: *Scheduler, irq_context: ?*CpuContext) void {
        self.current_process.preempt_count += 1;
        errdefer self.current_process.preempt_count -= 1;
        self.current_process.counter = 0;
        // round robin for processes
        var next_proc_pid: usize = 0;
        var c: isize = -1;
        while (true) {
            for (self.processses) |*process, i| {
                if (i >= self.pid_counter) break;
                if (process.state == .running and process.counter > c) {
                    c = process.counter;
                    next_proc_pid = i;
                }
            }

            if (c != 0) break;
            for (self.processses) |*process, i| {
                if (i >= self.pid_counter) break;
                process.counter = (process.counter >> 1) + process.priority;
            }
        }
        self.current_process.preempt_count -= 1;
        self.switchContextToProcess(&self.processses[next_proc_pid], irq_context);
    }

    pub fn timerIntEvent(self: *Scheduler, irq_context: *CpuContext) void {
        self.current_process.counter -= 1;
        for (self.processses_sleeping) |proc, i| {
            if (proc) |process| {
                if (process.sleep_counter <= 0) {
                    process.state = .running;
                    self.processses_sleeping[i] = null;
                } else {
                    process.sleep_counter -= 1;
                }
            }
        }
        if (self.current_process.counter > 0 or self.current_process.preempt_count > 0) {
            if (self.current_process.counter <= 0) kprint("self.current_process.preempt_count: {d} \n", .{self.current_process.preempt_count});
            if (log) kprint("--------- PROC WAIT counter: {d} \n", .{self.current_process.counter});
            // return all the way back to the exc vector table where cpu state is restored from the stack
            // if the task is dead already, we don't return back to the process but schedule the next task
            if (self.current_process.state == .running) return;
        }
        self.schedule(irq_context);
    }
    pub fn initAppsInScheduler(self: *Scheduler, apps: []const []const u8, topics: *Topics) !void {
        self.current_process.preempt_count += 1;
        defer self.current_process.preempt_count -= 1;
        for (apps) |app| {
            const req_pages = try std.math.divCeil(usize, board.config.mem.app_vm_mem_size, board.config.mem.va_user_space_gran.page_size);
            const app_mem = try self.page_allocator.allocNPage(req_pages);

            var pid = self.pid_counter;

            std.mem.copy(u8, app_mem, app);
            self.processses[pid].cpu_context.elr_el1 = 0;
            self.processses[pid].cpu_context.sp_el0 = alignForward(app.len + board.config.mem.app_stack_size, 16);
            self.processses[pid].cpu_context.x0 = pid;
            self.processses[pid].app_mem = app_mem;
            self.processses[pid].priority = self.current_process.priority;
            self.processses[pid].state = .running;
            self.processses[pid].priv_level = .user;
            self.processses[pid].counter = self.processses[pid].priority;
            self.processses[pid].preempt_count = 0;
            self.processses[pid].pid = pid;

            // initing the apps page-table
            {
                // MMU page dir config
                var page_table_write = try app_page_table.init(&self.processses[pid].page_table, self.kernel_lma_offset);
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

            // initing the apps topics-interface
            {
                // MMU page dir config
                var page_table_write = try app_page_table.init(&self.processses[pid].page_table, self.kernel_lma_offset);
                const topics_interace_mapping = mmu.Mapping{
                    .mem_size = topics.mem_pool.len,
                    .pointing_addr_start = self.kernel_lma_offset + board.config.mem.kernel_space_size + @ptrToInt(topics.mem_pool.ptr),
                    .virt_addr_start = 0x20000000,
                    .granule = board.boardConfig.Granule.Fourk,
                    .addr_space = .ttbr0,
                    .flags_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .read_write, .attrIndex = .mair0 },
                    .flags_non_last_lvl = mmu.TableDescriptorAttr{ .accessPerm = .read_write },
                };
                try page_table_write.mapMem(topics_interace_mapping);
            }
            self.processses[pid].ttbr0 = self.kernel_lma_offset + utils.toTtbr0(usize, @ptrToInt(&self.processses[pid].page_table));
            self.pid_counter += 1;
        }
    }

    pub fn killTask(self: *Scheduler, pid: usize) !void {
        self.current_process.preempt_count += 1;
        errdefer self.current_process.preempt_count -= 1;
        try self.checkForPid(pid);
        self.processses[pid].state = .dead;
        for (self.processses) |*proc| {
            if (proc.is_thread and proc.parent_pid == pid) {
                proc.state = .dead;
            }
        }
        self.current_process.preempt_count -= 1;
        self.schedule(null);
    }

    pub fn exitTask(self: *Scheduler) !noreturn {
        try self.killTaskAndChildrend(self.current_process.pid.?);
        while(true){}
    }

    // function is deprecated since new tasks cannot be created without allocating new memory which is not legal in system runtime
    // todo => find way around policy
    pub fn deepForkProcess(self: *Scheduler, to_clone_pid: usize) !void {
        self.current_process.preempt_count += 1;
        defer {
            self.current_process.preempt_count -= 1;
            self.switchMemContext(self.current_process.ttbr0.?, null);
        }

        // switching to boot userspace page table (which spans all apps in order to acces other apps memory with their relative userspace addresses...)
        self.switchMemContext(self.processses[0].ttbr0.?, null);

        try self.checkForPid(to_clone_pid);
        if (self.processses[to_clone_pid].priv_level == .boot) return Error.ForkPermissionFault;

        const req_pages = try std.math.divCeil(usize, board.config.mem.app_vm_mem_size, board.config.mem.va_user_space_gran.page_size);
        // todo => remove allcoation
        var new_app_mem = try self.page_allocator.allocNPage(req_pages);

        var new_pid = self.pid_counter;

        std.mem.copy(u8, new_app_mem, self.processses[to_clone_pid].app_mem.?);
        self.processses[new_pid] = self.processses[to_clone_pid];
        self.processses[new_pid].app_mem = new_app_mem;
        self.processses[new_pid].ttbr0 = self.kernel_lma_offset + utils.toTtbr0(usize, @ptrToInt(&self.processses[new_pid].page_table));
        self.processses[new_pid].pid = new_pid;
        self.processses[new_pid].parent_pid = to_clone_pid;
        self.processses[to_clone_pid].child_pid = new_pid;
        self.pid_counter += 1;

        for (self.processses) |*proc| {
            if (proc.is_thread or proc.parent_pid == to_clone_pid) {
                try self.cloneThread(proc.pid.?, new_pid);
            }
        }
    }

    pub fn cloneThread(self: *Scheduler, to_clone_thread_pid: usize, new_proc_pid: usize) !void {
        self.current_process.preempt_count += 1;
        defer self.current_process.preempt_count -= 1;
        try self.checkForPid(to_clone_thread_pid);
        if (!self.processses[to_clone_thread_pid].is_thread) return;

        var new_pid = self.pid_counter;
        self.processses[new_pid] = self.processses[to_clone_thread_pid];
        self.processses[new_pid].pid = new_pid;
        self.processses[new_pid].parent_pid = new_proc_pid;
        self.processses[new_pid].ttbr0 = self.processses[new_proc_pid].ttbr0;
        self.processses[new_pid].ttbr1 = self.processses[new_proc_pid].ttbr1;

        self.pid_counter += 1;
    }
    pub fn createThreadFromCurrentProcess(self: *Scheduler, entry_fn_ptr: *const anyopaque, thread_fn_ptr: *const anyopaque, thread_stack_addr: usize, args: *anyopaque) void {
        self.current_process.preempt_count += 1;
        defer self.current_process.preempt_count -= 1;
        var new_pid = self.pid_counter;
        self.processses[new_pid].pid = new_pid;
        self.processses[new_pid].is_thread = true;
        self.processses[new_pid].counter = self.processses[self.current_process.pid.?].priority;
        self.processses[new_pid].priority = self.processses[self.current_process.pid.?].priority;
        self.processses[new_pid].parent_pid = self.current_process.pid.?;
        self.processses[new_pid].cpu_context.x0 = @ptrToInt(thread_fn_ptr);
        self.processses[new_pid].cpu_context.x1 = @ptrToInt(args);
        self.processses[new_pid].cpu_context.elr_el1 = @ptrToInt(entry_fn_ptr);
        self.processses[new_pid].cpu_context.sp_el0 = thread_stack_addr;
        self.processses[new_pid].cpu_context.sp_el1 = thread_stack_addr;
        self.processses[new_pid].priv_level = self.processses[self.current_process.pid.?].priv_level;
        self.processses[new_pid].ttbr0 = self.processses[self.current_process.pid.?].ttbr0;
        self.processses[new_pid].ttbr1 = self.processses[self.current_process.pid.?].ttbr1;
        self.pid_counter += 1;
    }

    // provides a generic entry function (generic in regard to the thread and argument function since @call builtin needs them to properly invoke the thread start)
    pub fn KernelThreadInstance(comptime thread_fn: anytype, comptime Args: type) type {
        const ThreadFn = @TypeOf(thread_fn);
        return struct {
            pub fn threadEntry(entry_fn: *ThreadFn, entry_args: *Args) callconv(.C) void {
                @call(.{ .modifier = .auto }, entry_fn, entry_args.*);
            }
        };
    }
    // creates thread for current process
    // info: use only permitted at kernel boot/init
    pub fn createKernelThread(self: *Scheduler, app_alloc: *KernelAlloc, thread_fn: anytype, args: anytype) !void {
        const thread_stack_mem = try app_alloc.alloc(u8, board.config.mem.k_stack_size, 16);
        var thread_stack_start: []u8 = undefined;
        thread_stack_start.ptr = @intToPtr([*]u8, @ptrToInt(thread_stack_mem.ptr) + thread_stack_mem.len);
        thread_stack_start.len = thread_stack_mem.len;

        var arg_mem: []const u8 = undefined;
        arg_mem.ptr = @ptrCast([*]const u8, @alignCast(1, &args));
        arg_mem.len = @sizeOf(@TypeOf(args));

        std.mem.copy(u8, thread_stack_start, arg_mem);

        const entry_fn = &(KernelThreadInstance(thread_fn, @TypeOf(args)).threadEntry);
        var thread_fn_ptr = &thread_fn;

        const thread_stack_addr = @ptrToInt(thread_stack_start.ptr) - alignForward(@sizeOf(@TypeOf(args)), 16);
        const args_ptr = thread_stack_start.ptr;
        self.createThreadFromCurrentProcess(@ptrCast(*const anyopaque, entry_fn), @ptrCast(*const anyopaque, thread_fn_ptr), thread_stack_addr, @ptrCast(*anyopaque, args_ptr));
    }

    pub fn killTaskAndChildrend(self: *Scheduler, starting_pid: usize) !void {
        self.current_process.preempt_count += 1;
        errdefer self.current_process.preempt_count -= 1;
        try self.checkForPid(starting_pid);
        self.processses[starting_pid].state = .dead;
        var child_proc_pid: ?usize = starting_pid;
        while (child_proc_pid != null) {
            self.processses[child_proc_pid.?].state = .dead;
            for (self.processses) |*proc| {
                if (proc.is_thread and proc.parent_pid == child_proc_pid.?) {
                    proc.state = .dead;
                }
            }
            child_proc_pid = self.processses[child_proc_pid.?].child_pid;
        }
        self.current_process.preempt_count -= 1;
        self.schedule(null);
    }

    pub fn getCurrentProcessPid(self: *Scheduler) usize {
        return self.current_process.pid.?;
    }

    pub fn setProcessState(self: *Scheduler, pid: usize, state: Process.ProcessState, irq_context: ?*CpuContext) void {
        self.processses[pid].state = state;
        if (pid == self.current_process.pid and irq_context != null) self.schedule(irq_context.?);
    }

    pub fn setProcessAsleep(self: *Scheduler, pid: usize, sleep_time: usize, irq_context: *CpuContext) !void {
        try self.checkForPid(pid);
        for (self.processses_sleeping) |proc, i| {
            if (proc == null) {
                self.processses_sleeping[i] = &self.processses[pid];
            }
        }
        self.processses[pid].sleep_counter = sleep_time;
        self.processses[pid].state = .sleeping;
        self.schedule(irq_context);
    }

    fn checkForPid(self: *Scheduler, pid: usize) !void {
        if (pid > maxProcesss) return Error.PidNotFound;
        if (self.processses[pid].state == .dead) return Error.TaskIsDead;
    }

    // args (process pointers) are past via registers
    fn switchContextToProcess(self: *Scheduler, next_process: *Process, irq_context: ?*CpuContext) void {
        var prev_process = self.current_process;
        self.current_process = next_process;

        if (next_process.priv_level == .user) self.switchMemContext(next_process.ttbr0, null);

        switchCpuContext(self, prev_process, next_process, irq_context);
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

    // irq_context is optional in case the previous scheduled task is not needed anymore
    fn switchCpuContext(self: *Scheduler, from: *Process, to: *Process, irq_context: ?*CpuContext) void {
        kprint("current_procc: {*}, self.current_process.preempt_count: {d} \n", .{ self.current_process, self.current_process.preempt_count });
        if (log) {
            kprint("from: ({s}, {s}, {*}) to ({s}, {s}, {*}) \n", .{ @tagName(from.priv_level), @tagName(from.state), from, @tagName(to.priv_level), @tagName(to.state), to });
            kprint("current processses(n={d}): \n", .{self.pid_counter + 1});
            for (self.processses) |*proc, i| {
                if (i >= self.pid_counter) break;
                kprint("pid: {d} {s}, {s}, {s}, (is thread) {any} \n", .{ i, @tagName(proc.priv_level), @tagName(proc.priv_level), @tagName(proc.state), proc.is_thread });
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
};
