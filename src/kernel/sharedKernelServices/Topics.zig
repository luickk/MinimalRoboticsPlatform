const std = @import("std");
const utils = @import("utils");
const board = @import("board");
const env = @import("environment");
const TopicBufferTypes = env.envConfTemplate.EnvConfig.TopicBufferTypes;
const ProccessorRegMap = arm.processor.ProccessorRegMap;
const kprint = @import("periph").uart.UartWriter(.ttbr1).kprint;

const UserPageAllocator = @import("UserPageAllocator.zig").UserPageAllocator;
const Scheduler = @import("Scheduler.zig").Scheduler;
const arm = @import("arm");
const appLib = @import("appLib");
const Semaphore = @import("KSemaphore.zig").Semaphore;
const CpuContext = arm.cpuContext.CpuContext;

const topicBuffSize = 10240;
const maxWaitingTasks = 10;

// changes behaviour based on runtime information
pub const MultiBuff = struct {
    const Error = error{
        BuffOutOfSpace,
        MaxRollOvers,
    };
    buff: []u8,
    behaviour_type: TopicBufferTypes,
    curr_read_write_ptr: usize,

    scheduler: *Scheduler,

    pub fn init(scheduler: *Scheduler, buff_addr: usize, buff_len: usize, buff_type: TopicBufferTypes) MultiBuff {
        var buff: []u8 = undefined;
        buff.ptr = @intToPtr([*]u8, buff_addr);
        buff.len = buff_len;

        return .{ .buff = buff, .behaviour_type = buff_type, .curr_read_write_ptr = 0, .scheduler = scheduler };
    }

    pub fn write(self: *MultiBuff, data: []u8) !void {
        switch (self.behaviour_type) {
            .RingBuffer => {
                return self.write_ring_buff(data);
            },
            .ContinousBuffer => {
                return self.write_continous_buff(data);
            },
        }
    }

    pub fn read(self: *MultiBuff, ret_buff: []u8) !void {
        switch (self.behaviour_type) {
            .RingBuffer => {
                return self.read_ring_buff(ret_buff);
            },
            .ContinousBuffer => {
                return self.read_continous_buff(ret_buff);
            },
        }
    }

    pub fn write_ring_buff(self: *MultiBuff, data: []u8) !void {
        if (self.curr_read_write_ptr + data.len > self.buff.len) return Error.BuffOutOfSpace;
        std.mem.copy(u8, self.buff[self.curr_read_write_ptr..], data);
        self.curr_read_write_ptr += data.len;
    }

    pub fn read_ring_buff(self: *MultiBuff, ret_buff: []u8) !void {
        if (self.curr_read_write_ptr < ret_buff.len) return Error.BuffOutOfSpace;
        var data = self.buff[self.curr_read_write_ptr - ret_buff.len .. self.curr_read_write_ptr];
        self.curr_read_write_ptr -= ret_buff.len;

        const userspace_app_mapping_ret_buff = @intToPtr([]u8, @ptrToInt(self.scheduler.current_process.app_mem.?.ptr) + @ptrToInt(ret_buff.ptr));
        std.mem.copy(u8, userspace_app_mapping_ret_buff, data);
    }

    pub fn write_continous_buff(self: *MultiBuff, data: []u8) !void {
        var buff_pointer = try std.math.mod(usize, self.curr_read_write_ptr, self.buff.len);

        std.mem.copy(u8, self.buff[buff_pointer..], data[0..self.buff.len]);
        if (buff_pointer + data.len > self.buff.len) {
            std.mem.copy(u8, self.buff[0..], data[self.buff.len..]);
        }
        self.curr_read_write_ptr += data.len;
    }

    pub fn read_continous_buff(self: *MultiBuff, ret_buff: []u8) !void {
        var buff_pointer = try std.math.mod(usize, self.curr_read_write_ptr, self.buff.len);

        var lower_read_bound: usize = 0;
        if (buff_pointer > ret_buff.len) lower_read_bound = buff_pointer - ret_buff.len;
        var data = self.buff[lower_read_bound..buff_pointer];

        const userspace_app_mapping_ret_buff = @intToPtr([]u8, @ptrToInt(self.scheduler.current_process.app_mem.?.ptr) + @ptrToInt(ret_buff.ptr));
        std.mem.copy(u8, userspace_app_mapping_ret_buff, data);

        if (buff_pointer < ret_buff.len) {
            const rollover_size: usize = try std.math.sub(usize, buff_pointer, ret_buff.len);
            // only one rollver is supported
            if (rollover_size > self.buff.len) return Error.MaxRollOvers;

            var rolled_over_data = self.buff[self.buff.len - rollover_size .. self.buff.len];
            std.mem.copy(u8, @intToPtr([]u8, @ptrToInt(userspace_app_mapping_ret_buff.ptr) + data.len), rolled_over_data);
        }
    }
};

pub const Topic = struct {
    buff: MultiBuff,
    id: usize,
    opened: bool,
    waiting_tasks: [maxWaitingTasks]?Semaphore,
    n_waiting_taks: usize,

    pub fn init(scheduler: *Scheduler, topic_mem: []u8, id: usize, buff_type: TopicBufferTypes) Topic {
        return .{
            .buff = MultiBuff.init(scheduler, @ptrToInt(topic_mem.ptr), topic_mem.len, buff_type),
            .id = id,
            .opened = false,
            .waiting_tasks = [_]?Semaphore{null} ** maxWaitingTasks,
            .n_waiting_taks = 0,
        };
    }

    pub fn write(self: *Topic, data: []u8) !void {
        return self.buff.write(data);
    }

    pub fn read(self: *Topic, ret_buff: []u8) !void {
        try self.buff.read(ret_buff);
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
            topics[i] = Topic.init(scheduler, topics_mem[topicBuffSize * i .. ((topicBuffSize * i) + topicBuffSize)], topic_conf.id, topic_conf.buffer_type);
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

    pub fn write(self: *Topics, id: usize, data_ptr: *u8, len: usize) !void {
        // switching to boot userspace page table (which spans all apps in order to acces other apps memory with their relative userspace addresses...)
        self.scheduler.switchMemContext(self.scheduler.processses[0].ttbr0.?, null);
        defer self.scheduler.switchMemContext(self.scheduler.current_process.ttbr0.?, null);

        const userspace_app_mapping_data_addr = @ptrToInt(self.scheduler.current_process.app_mem.?.ptr) + @ptrToInt(data_ptr);
        if (self.findTopicById(id)) |index| {
            var data: []u8 = undefined;
            data.ptr = @intToPtr([*]u8, userspace_app_mapping_data_addr);
            data.len = len;
            try self.topics[index].write(data);
            for (self.topics[index].waiting_tasks) |*semaphore| {
                if (semaphore.* != null) {
                    semaphore.*.?.signal(self.scheduler);
                    semaphore.* = null;
                    self.topics[index].n_waiting_taks -= 1;
                }
            }
        }
    }

    pub fn read(self: *Topics, id: usize, ret_buff: []u8) !void {
        // switching to boot userspace page table (which spans all apps in order to acces other apps memory with their relative userspace addresses...)
        self.scheduler.switchMemContext(self.scheduler.processses[0].ttbr0.?, null);
        defer self.scheduler.switchMemContext(self.scheduler.current_process.ttbr0.?, null);

        if (self.findTopicById(id)) |index| {
            try self.topics[index].read(ret_buff);
        }
    }

    pub fn makeTaskWait(self: *Topics, topic_id: usize, pid: usize, irq_context: *CpuContext) void {
        if (self.findTopicById(topic_id)) |index| {
            // is increased before Semaphore wait call because that may invoke the scheduler which would thus not increase the counter
            self.topics[index].n_waiting_taks += 1;
            // todo => implement error if n_waiting_tasks is full
            self.topics[index].waiting_tasks[self.topics[index].n_waiting_taks - 1] = Semaphore.init(0);
            self.topics[index].waiting_tasks[self.topics[index].n_waiting_taks - 1].?.wait(pid, self.scheduler, irq_context);
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
