const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr1).kprint;
const board = @import("board");
const arm = @import("arm");
const proc = arm.processor.ProccessorRegMap(.el1);
const CpuContext = arm.cpuContext.CpuContext;

const b_options = @import("build_options");
const kernel_bin_size = b_options.kernel_bin_size;
const bl_bin_size = b_options.bl_bin_size;

pub const Task = packed struct {
    pub const TaskState = enum(usize) {
        running,
    };

    pub const TaskPageInfo = packed struct {
        base_pgd: usize,
        n_pages: usize,

        pub fn init() TaskPageInfo {
            comptime var no_rom_bl_bin_offset = 0;
            if (!board.config.mem.has_rom) no_rom_bl_bin_offset = bl_bin_size;
            return TaskPageInfo{
                .base_pgd = board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0) + no_rom_bl_bin_offset + board.config.mem.kernel_space_size,
                .n_pages = 0,
            };
        }
    };
    // !has to be first for context switch to find cpu_context!
    cpu_context: CpuContext,
    state: TaskState,
    counter: isize,
    priority: isize,
    preempt_count: isize,
    flags: usize,
    page_info: TaskPageInfo,

    pub fn init() Task {
        return Task{
            .cpu_context = CpuContext.init(),
            .state = .running,
            .counter = 0,
            .priority = 1,
            .preempt_count = 0,
            .flags = 0x00000002,
            .page_info = TaskPageInfo.init(),
        };
    }
    pub fn setPreempt(self: *Task, state: bool) void {
        if (state) self.preempt_count -= 1;
        if (!state) self.preempt_count += 1;
    }
};

const maxTasks = 10;

// globals

var current_task: ?*Task = blk: {
    var init_task = Task.init();
    break :blk &init_task;
};
var tasks = [_]?*Task{null} ** maxTasks;

var running_tasks: usize = 0;

pub fn Scheduler(comptime UserPageAllocator: type) type {
    return struct {
        const Self = @This();

        page_allocator: *UserPageAllocator,

        pub fn init(page_allocator: *UserPageAllocator) Self {
            // the init task contains all relevant mem&cpu context information of the "main" kernel process
            // and as such has the highest priority
            current_task.?.priority = 15;
            tasks[0] = current_task.?;
            running_tasks += 1;
            return Self{
                .page_allocator = page_allocator,
            };
        }

        pub fn schedule(self: *Self, irq_context: *CpuContext) void {
            _ = self;
            kprint("schdeuler caleed \n", .{});
            // current_task.?.counter -= 1;
            // if (current_task.?.counter > 0 or current_task.?.preempt_count > 0) return;
            current_task.?.counter = 0;

            current_task.?.setPreempt(false);
            var next: usize = 0;
            var c: isize = -1;
            while (true) {
                for (tasks) |*task, i| {
                    // kprint("task {d}: {any} \n", .{ i, task.*.?.* });
                    if (task.*.?.state == .running and task.*.?.counter > c) {
                        c = task.*.?.counter;
                        next = i;
                    }
                    // kprint("increasing {d} \n", .{task.*.?.counter});
                }

                if (c != 0) break;
                for (tasks) |*task| {
                    task.*.?.counter = (task.*.?.counter >> 1) + task.*.?.priority;
                }
            }
            switchContextToTask(tasks[next].?, irq_context);
            current_task.?.setPreempt(true);
        }

        pub fn timerIntEvent(self: *Self, irq_context: *CpuContext) void {
            current_task.?.counter -= 1;
            // kprint("{d} {d} \n", .{ current_task.?.counter, current_task.?.preempt_count });
            if (current_task.?.counter > 0 and current_task.?.preempt_count > 0) {
                kprint("returning.......... \n", .{});
                return;
            }
            current_task.?.counter = 0;

            proc.DaifReg.enableIrq();
            self.schedule(irq_context);
            proc.DaifReg.disableIrq();
        }

        pub fn copyProcessToTaskQueue(self: *Self, flags: usize, fnp: *const fn () void) !usize {
            current_task.?.setPreempt(false);
            // todo => make configurable
            const task_stack_size = 2048;

            var copied_task: *Task = @ptrCast(*Task, try self.page_allocator.allocNPage(2));
            copied_task.cpu_context.x19 = @ptrToInt(fnp);
            // arg0 is not supported for now
            copied_task.cpu_context.x20 = 0;
            copied_task.cpu_context.pc = @ptrToInt(&retFromFork);
            copied_task.cpu_context.sp = @ptrToInt(copied_task) + @sizeOf(Task) + task_stack_size;

            // setting base_pdg to allocated userspace page base
            copied_task.page_info.base_pgd = @ptrToInt(copied_task);

            copied_task.flags = flags;
            copied_task.priority = current_task.?.priority;
            copied_task.state = .running;
            copied_task.counter = copied_task.priority;
            copied_task.preempt_count = 1;

            var pid = running_tasks;
            tasks[pid] = copied_task;
            running_tasks += 1;

            current_task.?.setPreempt(true);
            return pid;
        }

        fn retFromFork() callconv(.C) void {
            current_task.?.setPreempt(false);
            asm volatile ("mov x0, x20");
            asm volatile ("blr x19");
        }

        // args (task pointers) are past via registers
        fn switchContextToTask(next_task: *Task, irq_context: *CpuContext) void {
            if (current_task.? == next_task) return;
            var prev_task = current_task.?;
            current_task.? = next_task;
            // changing ttbr0 page desc
            // switchMemContext(next_task.page_info.base_pgd);
            // chaning relevant regs including sp
            switchCpuContext(prev_task, next_task, irq_context);
        }

        // todo => simd regs?
        fn switchCpuContext(from: *Task, to: *Task, irq_context: *CpuContext) void {
            kprint("from: {*} to {*} \n", .{ from, to });
            // kprint("to sp: {x} \n", .{to.cpu_context.sp});
            from.cpu_context = irq_context.*;
            CpuContext.restoreContextFromStruct(&to.cpu_context);

            asm volatile ("eret");
        }

        fn switchMemContext(ttbr_0_addr: usize) void {
            asm volatile ("msr ttbr0_el1, %[ttbr0_addr]"
                :
                : [ttbr0_addr] "rax" (@ptrToInt(ttbr_0_addr)),
            );
            asm volatile ("tlbi vmalle1is");
            // ensure completion of TLB invalidation
            asm volatile ("dsb ish");
            asm volatile ("isb");
        }
    };
}
