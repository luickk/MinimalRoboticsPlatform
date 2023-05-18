const std = @import("std");
const utils = @import("utils");
const board = @import("board");
const kprint = @import("periph").uart.UartWriter(.ttbr1).kprint;

const UserPageAllocator = @import("UserPageAllocator.zig").UserPageAllocator;
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

    pub fn write(self: *Topic, data: []u8) !void {
        return self.circ_buff.write(data);
    }

    pub fn read(self: *Topic, len: usize) ![]u8 {
        return self.circ_buff.read(len);
    }
};

pub const Topics = struct {
    topics: [maxTopics]Topic,
    mem_pool: []u8,

    pub fn init(user_page_alloc: *UserPageAllocator) !Topics {
        const pages_req = (try std.math.mod(usize, maxTopics * topicBuffSize, board.config.mem.va_user_space_gran.page_size)) + 1;
        const topics_mem = try user_page_alloc.allocNPage(pages_req);
        var topics = [_]Topic{undefined} ** maxTopics;
        for (topics) |*topic, i| {
            topic.* = Topic.init(topics_mem[topicBuffSize * i .. ((topicBuffSize * i) + topicBuffSize)]);
        }
        return .{
            .topics = topics,
            .mem_pool = topics_mem,
        };
    }

    pub fn closeTopic(self: *Topics, index: usize) void {
        if (index <= self.topics.len) self.topics[index].opened = true;
    }

    pub fn openTopic(self: *Topics, index: usize) void {
        if (index <= self.topics.len) self.topics[index].opened = false;
    }

    pub fn push(self: *Topics, index: usize, data_ptr: *u8, len: usize) !void {
        if (index <= self.topics.len) {
            var data: []u8 = undefined;
            data.ptr = @ptrCast([*]u8, data_ptr);
            data.len = len;
            try self.topics[index].write(data);
        }
    }

    pub fn pop(self: *Topics, index: usize, len: usize) !?[]u8 {
        if (index <= self.topics.len - 1) {
            return try self.topics[index].read(len);
        }
        return null;
    }
};
