const std = @import("std");
const utils = @import("utils");
const board = @import("board");

const sharedKernelServices = @import("sharedKernelServices");
const UserPageAllocator = sharedKernelServices.UserPageAllocator;
const arm = @import("arm");

const topicBuffSize = 10240;

pub const Topic = struct {
    circ_buff: utils.CircBuff,

    pub fn init(topic_mem: [topicBuffSize]u8) Topic {
        return .{
            .circ_buff = utils.CircBuff.init(&topic_mem[0], topicBuffSize),
        };
    }

    pub fn write(self: *Topic, data: []u8) !void {
        return self.circ_buff.write(data);
    }

    pub fn read(self: *Topic, len: usize) !void {
        return self.circ_buff.read(len);
    }
};

pub const Topics = struct {
    topics: []Topic,
    mem_pool: []u8,

    pub fn init(max_topics: usize, user_page_alloc: UserPageAllocator) !Topics {
        const pages_req = (try std.math.mod(usize, max_topics * topicBuffSize, UserPageAllocator.page, board.config.mem.va_user_space_gran.page_size)) + 1;
        const topics_mem = try user_page_alloc.allocNPage(pages_req);

        var topics: []Topic = undefined;
        topics.len = max_topics;
        for (topics) |*topic, i| {
            topic.* = Topic.init(topics_mem[topicBuffSize * i .. (topicBuffSize * i) + topicBuffSize]);
        }

        return .{
            .topics = topics,
            .mem_pool = topics_mem,
        };
    }
};
