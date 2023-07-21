const std = @import("std");
const utils = @import("utils");
const board = @import("board");
const env = @import("environment");

const TopicBufferTypes = env.envConfTemplate.TopicBufferTypes;

const appLib = @import("appLib");
const sysCalls = appLib.sysCalls;
const kprint = appLib.sysCalls.SysCallPrint.kprint;

// todo => permission restrictions

// changes behaviour based on runtime information
pub const UsersapceMultiBuff = struct {
    const Error = error{
        MaxRollOvers,
    };
    buff: []u8,
    behaviour_type: TopicBufferTypes,

    // this is the only state which is restored, all other variables will reset upon each call when used by SharedMemTopicsInterface
    curr_read_write_ptr: *volatile usize,

    pub fn init(topic_mem: []u8, buff_curr_read_write_ptr_state: *volatile usize, buff_type: TopicBufferTypes) UsersapceMultiBuff {
        return .{ .buff = topic_mem, .behaviour_type = buff_type, .curr_read_write_ptr = buff_curr_read_write_ptr_state };
    }

    pub fn write(self: *UsersapceMultiBuff, data: []u8) !usize {
        switch (self.behaviour_type) {
            .RingBuffer => {
                return self.write_ring_buff(data);
            },
            .ContinousBuffer => {
                return self.write_continous_buff(data);
            },
        }
    }

    pub fn read(self: *UsersapceMultiBuff, ret_buff: []u8) !usize {
        switch (self.behaviour_type) {
            .RingBuffer => {
                return self.read_ring_buff(ret_buff);
            },
            .ContinousBuffer => {
                return self.read_continous_buff(ret_buff);
            },
        }
    }

    pub fn write_ring_buff(self: *UsersapceMultiBuff, data: []u8) !usize {
        var space_left: usize = 0;
        if (self.curr_read_write_ptr.* + data.len > self.buff.len) {
            space_left = self.buff.len - try std.math.mod(usize, self.curr_read_write_ptr.*, self.buff.len);
        } else space_left = data.len;
        std.mem.copy(u8, self.buff[self.curr_read_write_ptr.* .. self.curr_read_write_ptr.* + space_left], data);
        self.curr_read_write_ptr.* += data.len;
        return space_left;
    }

    pub fn read_ring_buff(self: *UsersapceMultiBuff, ret_buff: []u8) !usize {
        // if (asm volatile ("adr %[pc], ."
        //     : [pc] "=r" (-> usize),
        // ) < 0xFFFFFF8000000000) kprint("curr read curr_read_write_ptr: {any} \n", .{self.curr_read_write_ptr});
        var ret_data: []u8 = undefined;
        if (self.curr_read_write_ptr.* < ret_buff.len) {
            ret_data = self.buff[0..self.curr_read_write_ptr.*];
            self.curr_read_write_ptr.* = 0;
        } else {
            ret_data = self.buff[self.curr_read_write_ptr.* - ret_buff.len .. self.curr_read_write_ptr.*];
            self.curr_read_write_ptr.* -= ret_buff.len;
        }
        std.mem.copy(u8, ret_buff, ret_data);
        return ret_data.len;
    }

    pub fn write_continous_buff(self: *UsersapceMultiBuff, data: []u8) !usize {
        var buff_pointer = try std.math.mod(usize, self.curr_read_write_ptr.*, self.buff.len);

        std.mem.copy(u8, self.buff[buff_pointer..], data);
        if (buff_pointer + data.len > self.buff.len) {
            std.mem.copy(u8, self.buff[0..], data[self.buff.len..]);
        }
        self.curr_read_write_ptr.* += data.len;
        return data.len;
    }

    pub fn read_continous_buff(self: *UsersapceMultiBuff, ret_buff: []u8) !usize {
        // if (asm volatile ("adr %[pc], ."
        //     : [pc] "=r" (-> usize),
        // ) < 0xFFFFFF8000000000) kprint("curr read curr_read_write_ptr: {any} \n", .{self.curr_read_write_ptr.*});
        var buff_pointer = try std.math.mod(usize, self.curr_read_write_ptr.*, self.buff.len);

        var lower_read_bound: usize = 0;
        if (buff_pointer > ret_buff.len) lower_read_bound = buff_pointer - ret_buff.len;
        var data = self.buff[lower_read_bound..buff_pointer];

        std.mem.copy(u8, ret_buff, data);

        var rolled_over_data: []u8 = undefined;
        if (buff_pointer < ret_buff.len and buff_pointer != 0) {
            const rollover_size: usize = std.math.absCast(try std.math.sub(isize, @intCast(isize, buff_pointer), @intCast(isize, ret_buff.len)));
            // only one rollver is supported
            if (rollover_size > self.buff.len) return Error.MaxRollOvers;

            rolled_over_data = self.buff[self.buff.len - rollover_size .. self.buff.len];
            std.mem.copy(u8, @intToPtr([]u8, @ptrToInt(ret_buff.ptr) + data.len), rolled_over_data);
        }
        return data.len + rolled_over_data.len;
    }
};

pub fn Topic(comptime Semaphore: type) type {
    return struct {
        const Self = @This();

        buff: UsersapceMultiBuff,
        id: usize,
        opened: bool,
        waiting_tasks: [board.config.static_memory_reserves.topics_max_process_in_queue]?Semaphore,
        n_waiting_taks: usize,

        pub fn init(topics_mem: []u8, buff_curr_read_write_ptr_state: *volatile usize, id: usize, buff_type: TopicBufferTypes) Self {
            return .{
                .buff = UsersapceMultiBuff.init(topics_mem, buff_curr_read_write_ptr_state, buff_type),
                .id = id,
                .opened = false,
                .waiting_tasks = [_]?Semaphore{null} ** board.config.static_memory_reserves.topics_max_process_in_queue,
                .n_waiting_taks = 0,
            };
        }

        pub fn write(self: *Self, data: []u8) !usize {
            return self.buff.write(data);
        }

        pub fn read(self: *Self, ret_buff: []u8) !usize {
            return self.buff.read(ret_buff);
        }
    };
}
