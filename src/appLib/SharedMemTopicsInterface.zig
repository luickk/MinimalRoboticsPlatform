const sharedKernelServices = @import("sharedKernelServices");
const Scheduler = sharedKernelServices.Scheduler;

const std = @import("std");
const utils = @import("utils");
const board = @import("board");

pub const Topics = struct {
    topics: [env.env_config.conf_topics.len]Topic,
    mem_pool: []u8,
    scheduler: *Scheduler,

    // the scheduler is a double pointer because the Topics are inited before the scheduler, so the scheduler pointer changes
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
