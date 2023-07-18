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
const KSemaphore = @import("KSemaphore.zig").Semaphore;
const CpuContext = arm.cpuContext.CpuContext;
const Topic = @import("sharedServices").Topic(KSemaphore(1));
const alignForward = std.mem.alignForward;

pub const SysCallsTopicsInterface = struct {
    topics: [env.env_config.countTopics()]Topic,
    mem_pool: []u8,
    scheduler: *Scheduler,

    pub fn init(user_page_alloc: *UserPageAllocator, scheduler: *Scheduler) !SysCallsTopicsInterface {
        var accumulatedTopicsBuffSize: usize = 0;

        // todo => mapping index to index doesn't work anymore with other statuses that are not topics
        for (env.env_config.status_control) |*status_control_conf| {
            if (status_control_conf.*.status_type == .topic) {
                accumulatedTopicsBuffSize += status_control_conf.topic_conf.?.buffer_size + @sizeOf(usize);
            }
        }
        const pages_req = (try std.math.mod(usize, accumulatedTopicsBuffSize, board.config.mem.va_user_space_gran.page_size)) + 1;

        const topics_mem = try user_page_alloc.allocNPage(pages_req);
        var topics = [_]Topic{undefined} ** env.env_config.countTopics();
        var used_topics_mem: usize = 0;
        const topic_read_write_buff_ptr = @intToPtr(*volatile usize, used_topics_mem);
        for (env.env_config.status_control) |*status_control_conf, i| {
            if (status_control_conf.*.status_type == .topic) {
                topic_read_write_buff_ptr.* = 0;
                topics[i] = Topic.init(topics_mem[used_topics_mem + @sizeOf(usize) .. used_topics_mem + status_control_conf.topic_conf.?.buffer_size], topic_read_write_buff_ptr, status_control_conf.id, status_control_conf.topic_conf.?.buffer_type);
                used_topics_mem += status_control_conf.topic_conf.?.buffer_size;
            }
        }
        return .{
            .topics = topics,
            .mem_pool = topics_mem,
            .scheduler = scheduler,
        };
    }

    pub fn closeTopic(self: *SysCallsTopicsInterface, id: usize) void {
        if (self.findTopicById(id)) |index| {
            self.topics[index].opened = true;
        }
    }

    pub fn openTopic(self: *SysCallsTopicsInterface, id: usize) void {
        if (self.findTopicById(id)) |index| {
            self.topics[index].opened = false;
        }
    }

    pub fn write(self: *SysCallsTopicsInterface, id: usize, data_ptr: *u8, len: usize) !void {
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

    pub fn read(self: *SysCallsTopicsInterface, id: usize, ret_buff: []u8) !void {
        // switching to boot userspace page table (which spans all apps in order to acces other apps memory with their relative userspace addresses...)
        self.scheduler.switchMemContext(self.scheduler.processses[0].ttbr0.?, null);
        defer self.scheduler.switchMemContext(self.scheduler.current_process.ttbr0.?, null);
        var userspace_app_mapping_ret_buff = @intToPtr([]u8, @ptrToInt(self.scheduler.current_process.app_mem.?.ptr) + @ptrToInt(ret_buff.ptr));
        userspace_app_mapping_ret_buff.len = ret_buff.len;
        if (self.findTopicById(id)) |index| {
            try self.topics[index].read(userspace_app_mapping_ret_buff);
        }
    }

    pub fn makeTaskWait(self: *SysCallsTopicsInterface, topic_id: usize, pid: u16, irq_context: *CpuContext) !void {
        if (self.findTopicById(topic_id)) |index| {
            if (self.topics[index].n_waiting_taks > self.topics[index].waiting_tasks.len) {
                kprint("[panic] Topic maxWaitingTasks exceeded \n", .{});
                while (true) {}
            }
            // is increased before Semaphore wait call because that may invoke the scheduler which would thus not increase the counter
            self.topics[index].n_waiting_taks += 1;
            self.topics[index].waiting_tasks[self.topics[index].n_waiting_taks - 1] = KSemaphore(1).init(1);
            try self.topics[index].waiting_tasks[self.topics[index].n_waiting_taks - 1].?.wait(pid, self.scheduler, irq_context);
        }
    }

    // returns index
    fn findTopicById(self: *SysCallsTopicsInterface, id: usize) ?usize {
        for (self.topics) |*topic, i| {
            if (topic.id == id) return i;
        }
        return null;
    }
};
