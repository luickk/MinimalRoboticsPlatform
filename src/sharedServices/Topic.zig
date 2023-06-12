const std = @import("std");
const utils = @import("utils");
const board = @import("board");
const env = @import("environment");
const TopicBufferTypes = env.envConfTemplate.EnvConfig.TopicBufferTypes;

// const appLib = @import("appLib");
// const sysCalls = appLib.sysCalls;
// const kprint = appLib.sysCalls.SysCallPrint.kprint;

// todo => make configurable and implement err if exceeded
const maxWaitingTasks = 10;

// changes behaviour based on runtime information
pub const UsersapceMultiBuff = struct {
    const Error = error{
        BuffOutOfSpace,
        MaxRollOvers,
    };
    buff: []u8,
    behaviour_type: TopicBufferTypes,
    curr_read_write_ptr: usize,

    pub fn init(topic_mem: []u8, buff_type: TopicBufferTypes) UsersapceMultiBuff {
        return .{ .buff = topic_mem, .behaviour_type = buff_type, .curr_read_write_ptr = 0};
    }

    pub fn write(self: *UsersapceMultiBuff, data: []u8) !void {
        switch (self.behaviour_type) {
            .RingBuffer => {
                return self.write_ring_buff(data);
            },
            .ContinousBuffer => {
                return self.write_continous_buff(data);
            },
        }
    }

    pub fn read(self: *UsersapceMultiBuff, ret_buff: []u8) !void {
        switch (self.behaviour_type) {
            .RingBuffer => {
                return self.read_ring_buff(ret_buff);
            },
            .ContinousBuffer => {
                return self.read_continous_buff(ret_buff);
            },
        }
    }

    pub fn write_ring_buff(self: *UsersapceMultiBuff, data: []u8) !void {
        if (self.curr_read_write_ptr + data.len > self.buff.len) return Error.BuffOutOfSpace;
        std.mem.copy(u8, self.buff[self.curr_read_write_ptr..], data);
        self.curr_read_write_ptr += data.len;
    }

    pub fn read_ring_buff(self: *UsersapceMultiBuff, ret_buff: []u8) !void {
        if (self.curr_read_write_ptr < ret_buff.len) return Error.BuffOutOfSpace;
        var data = self.buff[self.curr_read_write_ptr - ret_buff.len .. self.curr_read_write_ptr];
        self.curr_read_write_ptr -= ret_buff.len;

        std.mem.copy(u8, ret_buff, data);
    }

    pub fn write_continous_buff(self: *UsersapceMultiBuff, data: []u8) !void {
        var buff_pointer = try std.math.mod(usize, self.curr_read_write_ptr, self.buff.len);

        std.mem.copy(u8, self.buff[buff_pointer..], data);
        if (buff_pointer + data.len > self.buff.len) {
            std.mem.copy(u8, self.buff[0..], data[self.buff.len..]);
        }
        self.curr_read_write_ptr += data.len;
    }

    pub fn read_continous_buff(self: *UsersapceMultiBuff, ret_buff: []u8) !void {
        var buff_pointer = try std.math.mod(usize, self.curr_read_write_ptr, self.buff.len);

        var lower_read_bound: usize = 0;
        if (buff_pointer > ret_buff.len) lower_read_bound = buff_pointer - ret_buff.len;
        var data = self.buff[lower_read_bound..buff_pointer];

        std.mem.copy(u8, ret_buff, data);

        if (buff_pointer < ret_buff.len) {
            const rollover_size: usize = try std.math.sub(usize, buff_pointer, ret_buff.len);
            // only one rollver is supported
            if (rollover_size > self.buff.len) return Error.MaxRollOvers;

            var rolled_over_data = self.buff[self.buff.len - rollover_size .. self.buff.len];
            std.mem.copy(u8, @intToPtr([]u8, @ptrToInt(ret_buff.ptr) + data.len), rolled_over_data);
        }
    }
};

pub fn Topic(comptime Semaphore: type) type {
    return struct {
        const Self = @This();

        buff: UsersapceMultiBuff,
        id: usize,
        opened: bool,
        waiting_tasks: [maxWaitingTasks]?Semaphore,
        n_waiting_taks: usize,

        pub fn init(topics_mem: []u8, id: usize, buff_type: TopicBufferTypes) Self {
            return .{
                .buff = UsersapceMultiBuff.init(topics_mem, buff_type),
                .id = id,
                .opened = false,
                .waiting_tasks = [_]?Semaphore{null} ** maxWaitingTasks,
                .n_waiting_taks = 0,
            };
        }

        pub fn write(self: *Self, data: []u8) !void {
            return self.buff.write(data);
        }

        pub fn read(self: *Self, ret_buff: []u8) !void {
            try self.buff.read(ret_buff);
        }
    };}