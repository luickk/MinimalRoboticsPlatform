pub const TopicTypePlaceHolder = struct {};

pub const StatusType = enum {
    string,
    usize,
    isize,
    bool,
    topic,

    pub fn statusTypeToType(comptime self: StatusType) ?type {
        switch (self) {
            inline .usize => return usize,
            inline .isize => return isize,
            inline .bool => return bool,
            inline .string => return []const u8,
            else => return null,
        }
    }

    pub fn isTypeEqual(self: StatusType, comptime inp_type: type) bool {
        switch (self) {
            inline .usize => if (inp_type == usize) return true,
            inline .isize => if (inp_type == isize) return true,
            inline .bool => if (inp_type == bool) return true,
            inline .string => if (inp_type == [100]u8) return true,
            else => return false,
        }
        return false;
    }

    pub fn statusTypeLen(self: StatusType) ?usize {
        switch (self) {
            .usize => return @sizeOf(usize),
            .isize => return @sizeOf(isize),
            .bool => return @sizeOf(bool),
            .string => return @sizeOf([]const u8),
            else => return null,
        }
    }
};
pub const TopicBufferTypes = enum {
    RingBuffer,
    ContinousBuffer,
};
pub const TopicConf = struct {
    buffer_type: TopicBufferTypes,
    buffer_size: usize,
    // permission_level:
};
pub const StatusControlConf = struct {
    status_type: StatusType,
    name: []const u8,
    id: u16,
    topic_conf: ?TopicConf,
};

pub fn EnvConfig(comptime n_statuses: usize) type {
    return struct {
        const Self = @This();
        const Error = error{ StatusNameNotFound, StatusTypeNotMatching, WrongStatusInterface };
        // comms model..
        status_control: [n_statuses]StatusControlConf,

        pub fn getStatusInfo(comptime self: *const Self, comptime name: []const u8) Error!struct { id: u16, type: type } {
            statuses: inline for (self.status_control) |status_control_conf| {
                comptime var found: bool = true;
                if (status_control_conf.name.len != name.len) {
                    found = false;
                    continue :statuses;
                }
                inline for (status_control_conf.name) |char, j| {
                    if (char != name[j]) {
                        found = false;
                        continue :statuses;
                    }
                }
                if (found == true) {
                    // if (!status_control_conf.status_type.isTypeEqual(@TypeOf(value))) return Error.StatusTypesNotMatching;
                    return .{ .id = status_control_conf.id, .type = status_control_conf.status_type.statusTypeToType() orelse Error.WrongStatusInterface };
                }
            }
            return Error.StatusNameNotFound;
        }

        pub fn countTopics(self: *const Self) usize {
            var n_topics: usize = 0;
            for (self.status_control) |*status_control_conf| {
                if (status_control_conf.*.status_type == .topic) n_topics += 1;
            }
            return n_topics;
        }

        pub fn countStatuses(self: *const Self) usize {
            var n_topics: usize = 0;
            for (self.status_control) |*status_control_conf| {
                if (status_control_conf.*.status_type != .topic) n_topics += 1;
            }
            return n_topics;
        }
    };
}
