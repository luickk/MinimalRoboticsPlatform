const std = @import("std");
const utils = @import("utils");
const board = @import("board");
const kprint = @import("periph").uart.UartWriter(.ttbr1).kprint;

const UserPageAllocator = @import("UserPageAllocator.zig").UserPageAllocator;
const Scheduler = @import("Scheduler.zig").Scheduler;
const arm = @import("arm");

const topicBuffSize = 10240;
const maxTopics = 100;

pub const Topic = struct {
    circ_buff: utils.CircBuff,
    opened: bool,

    pub fn init(topic_mem: []u8) Topic {
        kprint("init {d} \n", .{topic_mem.len});
        return .{
            .circ_buff = utils.CircBuff.init(@ptrToInt(topic_mem.ptr), topic_mem.len),
            .opened = false,
        };
    }

    pub fn push(self: *Topic, data: []u8) !void {
        return self.circ_buff.write(data);
    }

    pub fn pop(self: *Topic, len: usize) ![]u8 {
        return self.circ_buff.read(len);
    }
};

pub const Topics = struct {
    topics: [maxTopics]Topic,
    mem_pool: []u8,
    scheduler: *Scheduler,

    pub fn init(user_page_alloc: *UserPageAllocator, scheduler: *Scheduler) !Topics {
        const pages_req = (try std.math.mod(usize, maxTopics * topicBuffSize, board.config.mem.va_user_space_gran.page_size)) + 1;
        const topics_mem = try user_page_alloc.allocNPage(pages_req);
        var topics = [_]Topic{undefined} ** maxTopics;
        for (topics) |*topic, i| {
            topic.* = Topic.init(topics_mem[topicBuffSize * i .. ((topicBuffSize * i) + topicBuffSize)]);
        }
        return .{
            .topics = topics,
            .mem_pool = topics_mem,
            .scheduler = scheduler,
        };
    }

    pub fn closeTopic(self: *Topics, index: usize) void {
        if (index <= self.topics.len) self.topics[index].opened = true;
    }

    pub fn openTopic(self: *Topics, index: usize) void {
        if (index <= self.topics.len) self.topics[index].opened = false;
    }

    pub fn push(self: *Topics, index: usize, data_ptr: *u8, len: usize) !void {
        // switching to boot userspace page table (which spans all apps in order to acces other apps memory with their relative userspace addresses...)
        self.scheduler.switchMemContext(self.scheduler.processses[0].ttbr0.?, null);
        defer self.scheduler.switchMemContext(self.scheduler.current_process.ttbr0.?, null);

        const userspace_app_mapping_data_addr = @ptrToInt(self.scheduler.current_process.app_mem.?.ptr) + @ptrToInt(data_ptr);
        if (index <= self.topics.len) {
            var data: []u8 = undefined;
            data.ptr = @intToPtr([*]u8, userspace_app_mapping_data_addr);
            data.len = len;
            try self.topics[index].push(data);
        }
    }

    pub fn pop(self: *Topics, index: usize, ret_buff: []u8) !void {
        // switching to boot userspace page table (which spans all apps in order to acces other apps memory with their relative userspace addresses...)
        self.scheduler.switchMemContext(self.scheduler.processses[0].ttbr0.?, null);
        defer self.scheduler.switchMemContext(self.scheduler.current_process.ttbr0.?, null);
        if (index <= self.topics.len - 1) {
            var data = try self.topics[index].pop(ret_buff.len);
            const userspace_app_mapping_ret_buff = @intToPtr([]u8, @ptrToInt(self.scheduler.current_process.app_mem.?.ptr) + @ptrToInt(ret_buff.ptr));
            std.mem.copy(u8, userspace_app_mapping_ret_buff, data);
        }
    }
};
