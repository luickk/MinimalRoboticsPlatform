pub const envConfTemplate = @import("configTemplates").envConfigTemplate;
const TopicConf = envConfTemplate.EnvConfig.TopicConf;

pub const env_config = envConfTemplate.EnvConfig{
    .conf_topics = [_]TopicConf{
        .{
            .buffer_type = envConfTemplate.EnvConfig.TopicBufferTypes.ContinousBuffer,
            .buffer_size = 1024,
            .id = 1,
            .debug_desc = "test",
        },
    },
};
