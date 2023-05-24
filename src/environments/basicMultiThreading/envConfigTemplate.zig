pub const EnvConfig = struct {
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
    // comms model..
    conf_topics: [1]TopicConf,
};
