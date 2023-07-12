pub const TopicTypePlaceHolder = struct {};
pub const EnvConfig = struct {
    pub const StatusTypes = enum {
        string,
        usize,
        isize,
        topic
    };
    pub const TopicBufferTypes = enum {
        RingBuffer,
        ContinousBuffer,
    };
    pub const TopicConf = struct {
        buffer_type: TopicBufferTypes,
        buffer_size: usize,
        id: usize,
        debug_desc: []const u8,
        // permission_level:
    };
    pub const StatusControlConf = struct {
        status_type: StatusTypes,
        name: []const u8,
        topic_conf: ?TopicConf,
    };
    // comms model..
    status_control: [2]StatusControlConf,

    pub fn countTopics(self: *const EnvConfig) usize {
        var n_topics: usize = 0;
        for (self.status_control) |*status_control_conf| {
            if (status_control_conf.*.status_type == .topic) n_topics += 1; 
        }
        return n_topics;
    }
};