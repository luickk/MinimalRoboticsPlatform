const std = @import("std");
const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr1).kprint;
const board = @import("board");
const b_options = @import("build_options");
const arm = @import("arm");
const ProccessorRegMap = arm.processor.ProccessorRegMap;
const CpuContext = arm.cpuContext.CpuContext;

const bl_bin_size = 0x2000000;

pub const Process = packed struct {
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

    pub const ProcessPageInfo = packed struct {
        base_pgd: usize,
        n_pages: usize,

        pub fn init() ProcessPageInfo {
            comptime var no_rom_bl_bin_offset = 0;
            if (!board.config.mem.has_rom) no_rom_bl_bin_offset = bl_bin_size;
            return ProcessPageInfo{
                .base_pgd = board.config.mem.ram_start_addr + (board.config.mem.bl_load_addr orelse 0) + no_rom_bl_bin_offset + board.config.mem.kernel_space_size,
                .n_pages = 0,
            };
        }
    };
    cpu_context: CpuContext,
    type: ProcessType,
    state: ProcessState,
    counter: isize,
    priority: isize,
    preempt_count: isize,
    flags: usize,
    page_info: ProcessPageInfo,

    pub fn init() Process {
        return Process{
            .cpu_context = CpuContext.init(),
            .type = .user,
            .state = .running,
            .counter = 0,
            .priority = 1,
            .preempt_count = 1,
            .flags = 0x00000002,
            .page_info = ProcessPageInfo.init(),
        };
    }
    pub fn setPreempt(self: *Process, state: bool) void {
        if (state) self.preempt_count -= 1;
        if (!state) self.preempt_count += 1;
    }
};

const maxProcesss = 10;

// globals

var current_process: ?*Process = blk: {
    var init_process = Process.init();
    init_process.type = .boot;
    break :blk &init_process;
};
var processs = [_]?*Process{null} ** maxProcesss;

var running_processs: usize = 0;

pub fn Scheduler(comptime UserPageAllocator: type) type {
    return struct {
        const Self = @This();

        page_allocator: *UserPageAllocator,

        pub fn init(page_allocator: *UserPageAllocator) Self {
            // the init process contains all relevant mem&cpu context information of the "main" kernel process
            // and as such has the highest priority
            current_process.?.priority = 15;
            processs[0] = current_process.?;
            running_processs += 1;

            return Self{
                .page_allocator = page_allocator,
            };
        }

        // assumes that all process counter were inited to 0
        pub fn initProcessCounter(self: *Self) void {
            _ = self;
            for (processs) |*process| {
                process.*.?.counter = (process.*.?.counter >> 1) + process.*.?.priority;
            }
        }
        pub fn schedule(self: *Self, irq_context: *CpuContext) void {
            _ = self;
            // current_process.?.counter -= 1;
            // if (current_process.?.counter > 0 or current_process.?.preempt_count > 0) return;
            current_process.?.counter = 0;

            current_process.?.setPreempt(false);
            var next: usize = 0;
            var c: isize = -1;
            while (true) {
                for (processs) |*process, i| {
                    // kprint("process {d}: {any} \n", .{ i, process.*.?.* });
                    if (process.*.?.state == .running and process.*.?.counter > c) {
                        c = process.*.?.counter;
                        next = i;
                    }
                    // kprint("increasing {d} \n", .{process.*.?.counter});
                }

                if (c != 0) break;
                for (processs) |*process| {
                    process.*.?.counter = (process.*.?.counter >> 1) + process.*.?.priority;
                }
            }
            switchContextToProcess(processs[next].?, irq_context);
            current_process.?.setPreempt(true);
        }

        pub fn timerIntEvent(self: *Self, irq_context: *CpuContext) void {
            // kprint("{any} \n", .{irq_context});
            current_process.?.counter -= 1;
            if (current_process.?.counter > 0 and current_process.?.preempt_count > 0) {
                kprint("--------- WAIT WAIT el: {d} \n", .{ProccessorRegMap.getCurrentEl()});
                // kprint("--------- WAIT WAIT", .{});
                // return all the way back to the exc vector table where cpu state is restored from the stack
                return;
            }
            current_process.?.counter = 0;

            ProccessorRegMap.DaifReg.enableIrq();
            self.schedule(irq_context);
            ProccessorRegMap.DaifReg.disableIrq();
        }
        // var test_proc_pid = scheduler.copyProcessToProcessQueue(0, &testUserProcess) catch |e| {
        //         kprint("[panic] Scheduler copyProcessToProcessQueue error: {s} \n", .{@errorName(e)});
        //         k_utils.panic();
        //     };

        pub fn initAppsInScheduler(self: *Self, flags: usize, apps: []const []const u8) !void {
            // todo => make configurable
            const process_stack_size = 0x10000;
            current_process.?.setPreempt(false);
            for (apps) |app| {
                var app_mem: []u8 = undefined;
                app_mem.ptr = @ptrCast([*]u8, try self.page_allocator.allocNPage(2));
                app_mem.len = app.len + @sizeOf(Process) + process_stack_size;

                std.mem.copy(u8, app_mem, app);
                var copied_process: *Process = @intToPtr(*Process, app.len + @ptrToInt(app_mem.ptr));
                copied_process.cpu_context.elr_el1 = @ptrToInt(app_mem.ptr);
                // the sp is increased by the CpuContext size at first schedule(bc it has not been interrupted before)
                copied_process.cpu_context.sp = @ptrToInt(copied_process) + @sizeOf(Process) + process_stack_size;

                // setting base_pdg to allocated userspace page base
                copied_process.page_info.base_pgd = @ptrToInt(copied_process);

                copied_process.flags = flags;
                copied_process.priority = current_process.?.priority;
                copied_process.state = .running;
                copied_process.type = .user;
                copied_process.counter = copied_process.priority;
                copied_process.preempt_count = 1;

                var pid = running_processs;
                processs[pid] = copied_process;
                running_processs += 1;
            }
            current_process.?.setPreempt(true);
        }

        pub fn copyProcessToProcessQueue(self: *Self, flags: usize, processs_entry_addr: usize) !usize {
            current_process.?.setPreempt(false);
            // todo => make configurable
            const process_stack_size = 4096;

            var copied_process: *Process = @ptrCast(*Process, try self.page_allocator.allocNPage(2));
            copied_process.cpu_context.elr_el1 = processs_entry_addr;
            // the sp is increased by the CpuContext size at first schedule(bc it has not been interrupted before)
            copied_process.cpu_context.sp = @ptrToInt(copied_process) + @sizeOf(Process) + process_stack_size;

            // setting base_pdg to allocated userspace page base
            copied_process.page_info.base_pgd = @ptrToInt(copied_process);

            copied_process.flags = flags;
            copied_process.priority = current_process.?.priority;
            copied_process.state = .running;
            copied_process.type = .user;
            copied_process.counter = copied_process.priority;
            copied_process.preempt_count = 1;

            var pid = running_processs;
            processs[pid] = copied_process;
            running_processs += 1;

            current_process.?.setPreempt(true);
            return pid;
        }

        fn retFromFork() callconv(.C) void {
            current_process.?.setPreempt(false);
            asm volatile ("mov x0, x20");
            asm volatile ("blr x19");
        }

        // args (process pointers) are past via registers
        fn switchContextToProcess(next_process: *Process, irq_context: *CpuContext) void {
            if (current_process.? == next_process) {
                kprint("[kernel][scheduler] last processed executed \n", .{});
                return;
            }
            var prev_process = current_process.?;
            current_process.? = next_process;
            // changing ttbr0 page desc
            // switchMemContext(next_process.page_info.base_pgd);
            // chaning relevant regs including sp
            switchCpuContext(prev_process, next_process, irq_context);
        }

        fn switchCpuContext(from: *Process, to: *Process, irq_context: *CpuContext) void {
            kprint("from: {*} to {*} \n", .{ from, to });

            from.cpu_context = irq_context.*;
            // restore Context and erets
            CpuContext.restoreContextFromMem(&(to.cpu_context));
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
