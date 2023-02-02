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
const ThreadArgs = @import("appLib").sysCalls.ThreadArgs;
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
        sleeping,
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
    ThreadPermissionFault,
};
const maxProcesss = 10;

// globals

var processses = [_]Process{Process.init()} ** maxProcesss;
var processses_sleeping = [_]?*Process{null} ** maxProcesss;
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
        for (processses_sleeping) |proc, i| {
            if (proc) |process| {
                kprint("sleep counter: {d} \n", .{process.sleep_counter});
                if (process.sleep_counter <= 0) {
                    process.state = .running;
                    processses_sleeping[i] = null;
                    kprint("SLEEP DONE \n", .{});
                } else {
                    process.sleep_counter -= 1;
                }
            }
        }
        if (current_process.counter > 0 and current_process.preempt_count > 0) {
            kprint("--------- PROC WAIT pc: {x} \n", .{irq_context.elr_el1});
            // return all the way back to the exc vector table where cpu state is restored from the stack
            // if the task is done already, we don't return back to the process but schedule the next task
            if (current_process.state == .running) return;
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
            processses[pid].cpu_context.sp_el0 = alignForward(app.len + board.config.mem.app_stack_size, 16);
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

    pub fn killProcess(self: *Scheduler, pid: usize, irq_context: *CpuContext) !void {
        current_process.setPreempt(false);
        try checkForPid(pid);
        processses[pid].state = .done;
        for (processses) |*proc| {
            if (proc.is_thread and proc.parent_pid == pid) {
                proc.state = .done;
            }
        }
        current_process.setPreempt(true);
        self.schedule(irq_context);
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

        for (processses) |*proc| {
            if (proc.is_thread and proc.parent_pid == to_clone_pid) {
                try self.cloneThread(proc.pid.?, new_pid);
            }
        }

        switchMemContext(current_process.ttbr0.?, null);
        current_process.setPreempt(true);
    }

    pub fn cloneThread(self: *Scheduler, to_clone_thread_pid: usize, new_proc_pid: usize) !void {
        _ = self;
        try checkForPid(to_clone_thread_pid);
        current_process.setPreempt(false);
        if (!processses[to_clone_thread_pid].is_thread) return;

        var new_pid = pid_counter;
        processses[new_pid] = processses[to_clone_thread_pid];
        processses[new_pid].pid = new_pid;
        processses[new_pid].parent_pid = new_proc_pid;
        processses[new_pid].ttbr0 = processses[new_proc_pid].ttbr0;
        processses[new_pid].ttbr1 = processses[new_proc_pid].ttbr1;

        pid_counter += 1;
        current_process.setPreempt(true);
    }
    pub fn createThreadFromCurrentProcess(self: *Scheduler, entry_fn_ptr: *const anyopaque, thread_fn_ptr: *const anyopaque, thread_stack_addr: usize, args: *anyopaque) void {
        _ = self;
        current_process.setPreempt(false);
        var new_pid = pid_counter;
        processses[new_pid].pid = new_pid;
        processses[new_pid].is_thread = true;
        processses[new_pid].counter = processses[current_process.pid.?].priority;
        processses[new_pid].priority = processses[current_process.pid.?].priority;
        processses[new_pid].parent_pid = current_process.pid.?;
        processses[new_pid].cpu_context.x0 = @ptrToInt(thread_fn_ptr);
        processses[new_pid].cpu_context.x1 = @ptrToInt(args);
        processses[new_pid].cpu_context.elr_el1 = @ptrToInt(entry_fn_ptr);
        processses[new_pid].cpu_context.sp_el0 = thread_stack_addr;
        processses[new_pid].cpu_context.sp = thread_stack_addr;
        processses[new_pid].priv_level = processses[current_process.pid.?].priv_level;
        processses[new_pid].ttbr0 = processses[current_process.pid.?].ttbr0;
        processses[new_pid].ttbr1 = processses[current_process.pid.?].ttbr1;
        pid_counter += 1;
        current_process.setPreempt(true);
        if (current_process.pid.? == 0) kprint("CREATED \n", .{});
    }

    // provides a generic entry function (generic in regard to the thread and argument function since @call builtin needs them to properly invoke the thread start)
    fn KernelThreadInstance(comptime thread_fn: anytype, comptime Args: type) type {
        const ThreadFn = @TypeOf(thread_fn);
        return struct {
            fn threadEntry(entry_fn: *ThreadFn, entry_args: *Args) callconv(.C) void {
                @call(.{ .modifier = .auto }, entry_fn, entry_args.*);
            }
        };
    }
    // creates thread for current process
    pub fn createKernelThread(self: *Scheduler, app_alloc: *KernelAlloc, thread_fn: anytype, args: anytype) !void {
        // todo => make thread_stack_size configurable
        const thread_stack_mem = try app_alloc.alloc(u8, 0x10000, 16);
        var thread_stack_start: []u8 = undefined;
        thread_stack_start.ptr = @intToPtr([*]u8, @ptrToInt(thread_stack_mem.ptr) + thread_stack_mem.len);
        thread_stack_start.len = thread_stack_mem.len;

        var arg_mem: []const u8 = undefined;
        arg_mem.ptr = @ptrCast([*]const u8, @alignCast(1, &args));
        arg_mem.len = @sizeOf(@TypeOf(args));

        std.mem.copy(u8, thread_stack_start, arg_mem);

        const entry_fn = &(KernelThreadInstance(thread_fn, @TypeOf(args)).threadEntry);
        const thread_fn_ptr = &thread_fn;
        const thread_stack_addr = @ptrToInt(thread_stack_start.ptr) - alignForward(@sizeOf(@TypeOf(args)), 16);
        const args_ptr = thread_stack_start.ptr;
        self.createThreadFromCurrentProcess(@ptrCast(*const anyopaque, entry_fn), @ptrCast(*const anyopaque, thread_fn_ptr), thread_stack_addr, @ptrCast(*anyopaque, args_ptr));
    }

    pub fn killProcessAndChildrend(self: *Scheduler, starting_pid: usize, irq_context: *CpuContext) !void {
        current_process.setPreempt(false);
        try checkForPid(starting_pid);
        processses[starting_pid].state = .done;
        var child_proc_pid = @as(?usize, starting_pid);
        while (child_proc_pid != null) {
            processses[child_proc_pid.?].state = .done;
            // killing tasks threads...
            // todo => store tasks pids in parents proc instead of iterating...
            for (processses) |*proc| {
                if (proc.is_thread and proc.parent_pid == child_proc_pid.?) {
                    proc.state = .done;
                }
            }
            child_proc_pid = processses[child_proc_pid.?].child_pid;
        }
        current_process.setPreempt(true);
        self.schedule(irq_context);
    }

    pub fn getCurrentProcessPid(self: *Scheduler) usize {
        _ = self;
        return current_process.pid.?;
    }
    pub fn setProcessAsleep(self: *Scheduler, pid: usize, sleep_time: usize, irq_context: *CpuContext) !void {
        try checkForPid(pid);
        for (processses_sleeping) |proc, i| {
            if (proc == null) {
                processses_sleeping[i] = &processses[pid];
            }
        }
        processses[pid].sleep_counter = sleep_time;
        processses[pid].state = .sleeping;
        self.schedule(irq_context);
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
            kprint("pid: {d} {s}, {s}, {s}, (is thread) {any} \n", .{ i, @tagName(proc.priv_level), @tagName(proc.priv_level), @tagName(proc.state), proc.is_thread });
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
