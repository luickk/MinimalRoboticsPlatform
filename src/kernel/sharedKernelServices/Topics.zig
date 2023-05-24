const std = @import("std");
const utils = @import("utils");
const board = @import("board");
const env = @import("environment");
const TopicBufferTypes = env.envConfTemplate.EnvConfig.TopicBufferTypes;
const kprint = @import("periph").uart.UartWriter(.ttbr1).kprint;

const UserPageAllocator = @import("UserPageAllocator.zig").UserPageAllocator;
const Scheduler = @import("Scheduler.zig").Scheduler;
const arm = @import("arm");

const topicBuffSize = 10240;

// changes behaviour based on runtime information
pub const MultiBuff = struct {
    const Error = error{
        BuffOutOfSpace,
    };
    buff: []u8,
    behaviour_type: TopicBufferTypes,
    curr_read_write_ptr: usize,

    pub fn init(buff_addr: usize, buff_len: usize, buff_type: TopicBufferTypes) MultiBuff {
        var buff: []u8 = undefined;
        buff.ptr = @intToPtr([*]u8, buff_addr);
        buff.len = buff_len;

        return .{ .buff = buff, .behaviour_type = buff_type, .curr_read_write_ptr = 0 };
    }
    pub fn write(self: *MultiBuff, data: []u8) !void {
        if (self.curr_read_write_ptr + data.len > self.buff.len) return Error.BuffOutOfSpace;
        std.mem.copy(u8, self.buff[self.curr_read_write_ptr..], data);
        self.curr_read_write_ptr += data.len;
    }

    pub fn read(self: *MultiBuff, len: usize) ![]u8 {
        if (self.curr_read_write_ptr < len) return Error.BuffOutOfSpace;
        var res = self.buff[self.curr_read_write_ptr - len .. self.curr_read_write_ptr];
        self.curr_read_write_ptr -= len;
        return res;
    }
};

pub const Topic = struct {
    buff: MultiBuff,
    id: usize,
    opened: bool,

    pub fn init(topic_mem: []u8, id: usize, buff_type: TopicBufferTypes) Topic {
        kprint("init {d} \n", .{topic_mem.len});
        return .{
            .buff = MultiBuff.init(@ptrToInt(topic_mem.ptr), topic_mem.len, buff_type),
            .id = id,
            .opened = false,
        };
    }

    pub fn push(self: *Topic, data: []u8) !void {
        return self.buff.write(data);
    }

    pub fn pop(self: *Topic, len: usize) ![]u8 {
        kprint("current level: {d} \n", .{self.buff.curr_read_write_ptr});
        var ret = self.buff.read(len);
        return ret;
    }
};

pub const Topics = struct {
    topics: [env.env_config.conf_topics.len]Topic,
    mem_pool: []u8,
    scheduler: *Scheduler,

    pub fn init(user_page_alloc: *UserPageAllocator, scheduler: *Scheduler) !Topics {
        const pages_req = (try std.math.mod(usize, env.env_config.conf_topics.len * topicBuffSize, board.config.mem.va_user_space_gran.page_size)) + 1;
        const topics_mem = try user_page_alloc.allocNPage(pages_req);
        var topics = [_]Topic{undefined} ** env.env_config.conf_topics.len;
        for (env.env_config.conf_topics) |topic_conf, i| {
            topics[i] = Topic.init(topics_mem[topicBuffSize * i .. ((topicBuffSize * i) + topicBuffSize)], topic_conf.id, topic_conf.buffer_type);
        }
        return .{
            .topics = topics,
            .mem_pool = topics_mem,
            .scheduler = scheduler,
        };
    }

    pub fn closeTopic(self: *Topics, id: usize) void {
        if (self.findTopicById(id)) |index| {
            self.topics[index].opened = true;
        }
    }

    pub fn openTopic(self: *Topics, id: usize) void {
        if (self.findTopicById(id)) |index| {
            self.topics[index].opened = false;
        }
    }

    pub fn push(self: *Topics, id: usize, data_ptr: *u8, len: usize) !void {
        // switching to boot userspace page table (which spans all apps in order to acces other apps memory with their relative userspace addresses...)
        self.scheduler.switchMemContext(self.scheduler.processses[0].ttbr0.?, null);
        defer self.scheduler.switchMemContext(self.scheduler.current_process.ttbr0.?, null);

        const userspace_app_mapping_data_addr = @ptrToInt(self.scheduler.current_process.app_mem.?.ptr) + @ptrToInt(data_ptr);
        if (self.findTopicById(id)) |index| {
            var data: []u8 = undefined;
            data.ptr = @intToPtr([*]u8, userspace_app_mapping_data_addr);
            data.len = len;
            try self.topics[index].push(data);
        }
    }

    pub fn pop(self: *Topics, id: usize, ret_buff: []u8) !void {
        // switching to boot userspace page table (which spans all apps in order to acces other apps memory with their relative userspace addresses...)
        self.scheduler.switchMemContext(self.scheduler.processses[0].ttbr0.?, null);
        defer self.scheduler.switchMemContext(self.scheduler.current_process.ttbr0.?, null);
        if (self.findTopicById(id)) |index| {
            var data = try self.topics[index].pop(ret_buff.len);
            const userspace_app_mapping_ret_buff = @intToPtr([]u8, @ptrToInt(self.scheduler.current_process.app_mem.?.ptr) + @ptrToInt(ret_buff.ptr));
            std.mem.copy(u8, userspace_app_mapping_ret_buff, data);
        }
    }

    // returns index
    fn findTopicById(self: *Topics, id: usize) ?usize {
        for (self.topics) |*topic, i| {
            if (topic.id == id) return i;
        }
        return null;
    }
};

test "MultiBuff test" {
    var buff = [_]u8{0} ** 2048;
    var rb = MultiBuff.init(@ptrToInt(&buff), buff.len);
    var counter: u8 = 5;
    try rb.write(&[_]u8{counter});
    try std.testing.expect((try rb.read(1))[0] == counter);
    try std.testing.expectError(MultiBuff.Error.BuffOutOfSpace, rb.read(1));
    counter += 5;
    try rb.write(&[_]u8{counter});
    try std.testing.expect((try rb.read(1))[0] == counter);
    counter += 5;
    try rb.write(&[_]u8{counter});
    try std.testing.expect((try rb.read(1))[0] == counter);
    counter += 5;
    try rb.write(&[_]u8{counter});
    try std.testing.expect((try rb.read(1))[0] == counter);
}
