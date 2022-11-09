const UserPageAllocator = @import("UserPageAllocator.zig").UserPageAllocator;

pub const Task: packed struct {
    pub const TaskState = enum(usize) {
        running,
    };

    pub const TaskPageInfo = struct {
        base_pgd: ?usize,
        n_pages: usize,
        pub fn reset(self: *TaskPageInfo) void {
            self.base_pgd = null;
            self.n_pages = 0;
        }
    };
    pub const CpuContext = struct {
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

        pub fn reset(self: *CpuContext) void {
            self.x19 = 0;
            self.x20 = 0;
            self.x21 = 0;
            self.x22 = 0;
            self.x23 = 0;
            self.x24 = 0;
            self.x25 = 0;
            self.x26 = 0;
            self.x27 = 0;
            self.x28 = 0;
            self.fp = 0;
            self.sp = 0;
            self.pc = 0;
        }
    };
    // !has to be first for context switch to find cpu_context!
    cpu_context: CpuContext,
    state: TaskState,
    counter: usize,
    priority: usize,
    preempt_count: usize,
    flags: usize,
    page_info: TaskPageInfo,

    pub fn reset(self: *Task) void {
        self.cpu_context.reset();
        self.state = 0;
        self.counter = 0;
        self.priority = 0;
        self.preempt_count = 0;
        self.flags = 0x00000002;
        page_info.reset();
    }
};

//globals

pub fn Scheduler(UserPageAllocator: type, max_tasks: usize, n_pages_per_task: usize) type {
    return struct {
        const Self = @This();

        page_allocator: *UserPageAllocator,

        pub fn init(page_allocator: *UserPageAllocator) Self {
            return Self{
                .page_allocator = page_allocator,
            };
        }

        pub fn schedule() noreturn {}
    };
}
