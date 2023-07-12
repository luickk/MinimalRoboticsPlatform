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
// const Topic = @import("sharedServices").Topic(sharedKernelServices.KSemaphore);

pub const SharedMemTopicsInterface = struct {
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
        fixedTopicMemPoolInterface.ptr = @intToPtr([*]u8 , 0x20000000);
        fixedTopicMemPoolInterface.len = pages_req * board.config.mem.va_user_space_gran.page_size;

        var used_topics_mem: usize = 0;
        for (env.env_config.status_control) |*status_control_conf, i| {
            if (status_control_conf.*.status_type == .topic) {
                // + @sizeOf(usize) bytes for the buff_state
                topics[i] = Topic.init(fixedTopicMemPoolInterface[used_topics_mem + @sizeOf(usize) .. used_topics_mem + status_control_conf.topic_conf.?.buffer_size], @intToPtr(*volatile usize, @ptrToInt(fixedTopicMemPoolInterface.ptr) + used_topics_mem), status_control_conf.topic_conf.?.id, status_control_conf.topic_conf.?.buffer_type);        
                used_topics_mem += status_control_conf.topic_conf.?.buffer_size;
            }
        }

        return .{
            .topics = topics,
            .mem_pool = fixedTopicMemPoolInterface,        
        };
    }


    pub fn read(self: *SharedMemTopicsInterface, id: usize, ret_buff: []u8) !void {
        if (self.findTopicById(id)) |index| {
            try self.topics[index].read(ret_buff);
        }
    }

    pub fn write(self: *SharedMemTopicsInterface, id: usize, data: []u8) !void {
        if (self.findTopicById(id)) |index| {
            try self.topics[index].write(data);
        }
    }

    // returns index
    fn findTopicById(self: *SharedMemTopicsInterface, id: usize) ?usize {
        for (self.topics) |*topic, i| {
            if (topic.id == id) return i;
        }
        return null;
    }
};
