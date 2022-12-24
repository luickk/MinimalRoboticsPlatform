const board = @import("board");

const b_options = @import("build_options");
const kernel_bin_size = b_options.kernel_bin_size;
const bl_bin_size = b_options.bl_bin_size;

pub const KernelAllocator = @import("KernelAllocator.zig").KernelAllocator;

const UserPageAllocatorTr = @import("UserPageAllocator.zig").UserPageAllocator;
const SchedulerTr = @import("Scheduler.zig").Scheduler;

// todo => put that somewhere more explicit....

pub const UserPageAllocator = UserPageAllocatorTr(board.config.mem.user_space_size, board.config.mem.va_layout.va_user_space_gran) catch |e| {
    @compileError(@errorName(e));
};
pub const Scheduler = SchedulerTr(UserPageAllocator);
