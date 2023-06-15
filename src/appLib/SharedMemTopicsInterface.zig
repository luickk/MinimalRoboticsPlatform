const sharedKernelServices = @import("sharedKernelServices");
const env = @import("environment");

const std = @import("std");
const utils = @import("utils");
const board = @import("board");
const Semaphore = @import("Semaphore.zig");

// const sysCalls = @import("userSysCallInterface.zig");
// const kprint = sysCalls.SysCallPrint.kprint;

const Topic = @import("sharedServices").Topic(Semaphore);
// const Topic = @import("sharedServices").Topic(sharedKernelServices.KSemaphore);

pub const SharedMemTopicsInterface = struct {
    topics: [env.env_config.conf_topics.len]Topic,
    topics_buff_state_mem: []usize,
    mem_pool: []u8,

    pub fn init() !SharedMemTopicsInterface {
        var topics = [_]Topic{undefined} ** env.env_config.conf_topics.len;
        
        var accumulatedTopicsBuffSize: usize = 0;
        for (env.env_config.conf_topics) |topic_conf| {
            accumulatedTopicsBuffSize += topic_conf.buffer_size;
        }
        const pages_req = (try std.math.mod(usize, accumulatedTopicsBuffSize, board.config.mem.va_user_space_gran.page_size)) + 1;
        var fixedTopicMemPoolInterface: []u8 = undefined;
        fixedTopicMemPoolInterface.ptr = @intToPtr([*]u8 , 0x20000000);
        var used_topics_mem: usize = 0;

        var topics_buff_state_mem: []usize = undefined;
        topics_buff_state_mem.ptr = @intToPtr([*]usize , 0x20000000);
        topics_buff_state_mem.len = env.env_config.conf_topics.len * 8;

        used_topics_mem += topics_buff_state_mem.len;
        fixedTopicMemPoolInterface.len = pages_req * board.config.mem.va_user_space_gran.page_size;
        for (env.env_config.conf_topics) |topic_conf, i| {
            // todo => align 
            // used_topics_mem = @ptrToInt(@alignCast(8, @intToPtr(*u8, used_topics_mem)));
            topics[i] = Topic.init(fixedTopicMemPoolInterface, topic_conf.id, topic_conf.buffer_type);        
        }
        return .{
            .topics = topics,
            .topics_buff_state_mem = topics_buff_state_mem,
            .mem_pool = fixedTopicMemPoolInterface,        };
    }


    pub fn read(self: *SharedMemTopicsInterface, id: usize, ret_buff: []u8) !void {
        if (self.findTopicById(id)) |index| {
            self.restoreTopicsBuffStateFromMem();
            try self.topics[index].read(ret_buff);
            self.saveTopicsBuffStateToMem();
        }
    }

    // todo => imeplement topic push notifications
    pub fn write(self: *SharedMemTopicsInterface, id: usize, data: []u8) !void {
        if (self.findTopicById(id)) |index| {
            self.restoreTopicsBuffStateFromMem();
            try self.topics[index].write(data);
            self.saveTopicsBuffStateToMem();
            // for (self.topics[index].waiting_tasks) |*semaphore| {
            //     if (semaphore.* != null) {
            //         semaphore.*.?.signal(self.scheduler);
            //         semaphore.* = null;
            //         self.topics[index].n_waiting_taks -= 1;
            //     }
            // }
        }
    }



    pub fn restoreTopicsBuffStateFromMem(self: *SharedMemTopicsInterface) void {
        for (self.topics) |*topic, i| {
            topic.*.buff.curr_read_write_ptr = self.topics_buff_state_mem[i];
        }
    }

    pub fn saveTopicsBuffStateToMem(self: *SharedMemTopicsInterface) void {
        var buff_state_arr = [_]usize{0} ** env.env_config.conf_topics.len;
        for (self.topics) |topic, i| {
            buff_state_arr[i] = topic.buff.curr_read_write_ptr;
        }
        std.mem.copy(usize, self.topics_buff_state_mem, &buff_state_arr);
    }

    // pub fn makeTaskWait(self: *SharedMemTopicsInterface, topic_id: usize, pid: usize, irq_context: *CpuContext) void {
    //     if (self.findTopicById(topic_id)) |index| {
    //         // // is increased before Semaphore wait call because that may invoke the scheduler which would thus not increase the counter
    //         // self.topics[index].n_waiting_taks += 1;
    //         // // todo => implement error if n_waiting_tasks is full
    //         // self.topics[index].waiting_tasks[self.topics[index].n_waiting_taks - 1] = Semaphore.init(0);
    //         // self.topics[index].waiting_tasks[self.topics[index].n_waiting_taks - 1].?.wait(pid, self.scheduler, irq_context);
    //     }
    // }

    // returns index
    fn findTopicById(self: *SharedMemTopicsInterface, id: usize) ?usize {
        for (self.topics) |*topic, i| {
            if (topic.id == id) return i;
        }
        return null;
    }
};
