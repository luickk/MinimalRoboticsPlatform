const sharedKernelServices = @import("sharedKernelServices");
const env = @import("environment");

const std = @import("std");
const utils = @import("utils");
const board = @import("board");
const Semaphore = @import("Semaphore.zig");

const sysCalls = @import("userSysCallInterface.zig");
const kprint = sysCalls.SysCallPrint.kprint;

const alignForward = std.mem.alignForward;
const Topic = @import("sharedServices").Topic(Semaphore);

pub const SharedMemTopicsInterface = struct {
    const Error = error{
        TopicIdNotFound,
        StatusInterfaceMissmatch,
    };

    topics: [env.env_config.countTopics()]Topic,
    mem_pool: []u8,

    pub fn init() !SharedMemTopicsInterface {
        var topics = [_]Topic{undefined} ** env.env_config.countTopics();

        var accumulatedTopicsBuffSize: usize = 0;
        for (env.env_config.status_control) |*status_control_conf| {
            if (status_control_conf.*.status_type == .topic) {
                accumulatedTopicsBuffSize += status_control_conf.topic_conf.?.buffer_size + @sizeOf(usize);
            }
        }
        const pages_req = (try std.math.mod(usize, alignForward(accumulatedTopicsBuffSize, 8), board.config.mem.va_user_space_gran.page_size)) + 1;
        var fixedTopicMemPoolInterface: []u8 = undefined;
        fixedTopicMemPoolInterface.ptr = @as([*]u8, @ptrFromInt(0x20000000));
        fixedTopicMemPoolInterface.len = pages_req * board.config.mem.va_user_space_gran.page_size;

        var used_topics_mem: usize = 0;
        var i: usize = 0;
        for (env.env_config.status_control) |*status_control_conf| {
            if (status_control_conf.*.status_type == .topic) {
                const topic_read_write_buff_ptr = @as(*volatile usize, @ptrFromInt(@intFromPtr(fixedTopicMemPoolInterface.ptr) + used_topics_mem));
                topic_read_write_buff_ptr.* = 0;
                // + @sizeOf(usize) bytes for the buff_state
                topics[i] = Topic.init(fixedTopicMemPoolInterface[used_topics_mem + @sizeOf(usize) .. used_topics_mem + status_control_conf.topic_conf.?.buffer_size], topic_read_write_buff_ptr, status_control_conf.id, status_control_conf.topic_conf.?.buffer_type);
                used_topics_mem += status_control_conf.topic_conf.?.buffer_size;
                i += 1;
            }
        }

        return .{
            .topics = topics,
            .mem_pool = fixedTopicMemPoolInterface,
        };
    }

    pub fn read(self: *SharedMemTopicsInterface, comptime name: []const u8, ret_buff: []u8) !usize {
        const status = try env.env_config.getStatusInfo(name);
        if (status.type != null) return Error.StatusInterfaceMissmatch;
        if (self.findTopicById(status.id)) |index| {
            return self.topics[index].read(ret_buff);
        } else return Error.TopicIdNotFound;
    }

    pub fn write(self: *SharedMemTopicsInterface, comptime name: []const u8, data: []u8) !usize {
        const status = try env.env_config.getStatusInfo(name);
        if (status.type != null) return Error.StatusInterfaceMissmatch;
        if (self.findTopicById(status.id)) |index| {
            return self.topics[index].write(data);
        } else return Error.TopicIdNotFound;
    }

    // returns index
    fn findTopicById(self: *SharedMemTopicsInterface, id: usize) ?usize {
        for (self.topics, 0..) |*topic, i| {
            if (topic.id == id) return i;
        }
        return null;
    }
};
