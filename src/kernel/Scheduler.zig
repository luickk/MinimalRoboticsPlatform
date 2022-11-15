const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr1).kprint;
const board = @import("board");
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
    pub const CpuContext = packed struct {
        x19: usize,
        x20: usize,
        x21: usize,
        x22: usize,
        x23: usize,
        x24: usize,
        x25: usize,
        x26: usize,
        x27: usize,
        x28: usize,
        fp: usize,
        sp: usize,
        pc: usize,

        pub fn init() CpuContext {
            return CpuContext{ .x19 = 0, .x20 = 0, .x21 = 0, .x22 = 0, .x23 = 0, .x24 = 0, .x25 = 0, .x26 = 0, .x27 = 0, .x28 = 0, .fp = 0, .sp = 0, .pc = 0 };
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

//globals
var init_task = Task.init();
var current_task: ?*Task = &init_task;
var tasks = [_]?*Task{null} ** maxTasks;

var running_tasks: usize = 0;

pub fn Scheduler(comptime UserPageAllocator: type) type {
    return struct {
        const Self = @This();

        page_allocator: *UserPageAllocator,

        pub fn init(page_allocator: *UserPageAllocator) Self {
            // the init task contains all relevant mem&cpu context information of the "main" kernel process
            // and as such has the highest priority
            init_task.priority = 15;
            tasks[0] = &init_task;
            running_tasks += 1;
            return Self{
                .page_allocator = page_allocator,
            };
        }

        pub fn schedule(self: *Self) void {
            _ = self;
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
            switchContextToTask(tasks[next].?);
            current_task.?.setPreempt(true);
        }

        pub fn copyProcessToTaskQueue(self: *Self, flags: usize, fnp: *const fn () void) !usize {
            current_task.?.setPreempt(false);

            comptime var no_rom_bl_bin_offset = 0;
            if (!board.config.mem.has_rom) no_rom_bl_bin_offset = bl_bin_size;

            var copied_task: *Task = @ptrCast(*Task, try self.page_allocator.allocNPage(2));
            copied_task.cpu_context.x19 = @ptrToInt(fnp);
            // arg0 is not supported for now
            copied_task.cpu_context.x20 = 0;
            copied_task.cpu_context.pc = @ptrToInt(&retFromFork);
            copied_task.cpu_context.sp = @ptrToInt(&copied_task.cpu_context);

            // setting base_pdg to allocated userspace page base
            copied_task.page_info.base_pgd = board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0) + no_rom_bl_bin_offset + board.config.mem.kernel_space_size + @ptrToInt(copied_task);

            copied_task.flags = flags;
            copied_task.priority = current_task.?.priority;
            copied_task.state = .running;
            copied_task.counter = copied_task.priority;
            copied_task.preempt_count = 1;

            var pid = running_tasks;
            tasks[pid] = copied_task;
            running_tasks += 1;

            current_task.?.setPreempt(false);
            return pid;
        }

        fn retFromFork() callconv(.C) void {
            current_task.?.setPreempt(false);
            asm volatile ("mov x0, x20");
            asm volatile ("blr x19");
        }

        // args (task pointers) are past via registers
        fn switchContextToTask(next_task: *Task) void {
            if (current_task.? == next_task) return;
            var prev_task = current_task.?;
            current_task.? = next_task;
            // changing ttbr0 page desc
            // switchMemContext(next_task.page_info.base_pgd);
            // chaning relevant regs including sp
            switchCpuContext(prev_task, next_task);
        }

        fn switchCpuContext(from: *Task, to: *Task) callconv(.C) void {
            kprint("from: {*} to {*} \n", .{ from, to });

            asm volatile ("mov x8, %[from_addr]"
                :
                : [from_addr] "rax" (@ptrToInt(from)),
            );

            asm volatile ("mov x9, sp");
            // store callee-saved registers
            asm volatile ("stp x19, x20, [x8], #16");
            asm volatile ("stp x21, x22, [x8], #16");
            asm volatile ("stp x23, x24, [x8], #16");
            asm volatile ("stp x25, x26, [x8], #16");
            asm volatile ("stp x27, x28, [x8], #16");
            asm volatile ("stp x29, x9, [x8], #16");
            asm volatile ("str x30, [x8]");

            asm volatile ("mov x8, %[to_addr]"
                :
                : [to_addr] "rax" (@ptrToInt(to)),
            );
            // restore callee regs
            asm volatile ("ldp x19, x20, [x8], #16");
            asm volatile ("ldp x21, x22, [x8], #16");
            asm volatile ("ldp x23, x24, [x8], #16");
            asm volatile ("ldp x25, x26, [x8], #16");
            asm volatile ("ldp x27, x28, [x8], #16");
            asm volatile ("ldp x29, x9, [x8], #16");
            asm volatile ("ldr x30, [x8]");
            asm volatile ("mov sp, x9");
            asm volatile ("ret");
        }

        fn switchMemContext(ttbr_0_addr: usize) callconv(.C) void {
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