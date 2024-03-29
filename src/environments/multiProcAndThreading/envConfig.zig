pub const envConfTemplate = @import("configTemplates").envConfigTemplate;
const StatusControlConf = envConfTemplate.StatusControlConf;

pub const env_config = envConfTemplate.EnvConfig(2){
    .status_control = [_]StatusControlConf{
        .{
            .status_type = .isize,
            .name = "height",
            .id = 0,
            .topic_conf = null,
        },
        .{
            .status_type = .topic,
            .name = "height-sensor",
            .id = 1,
            .topic_conf = .{
                .buffer_type = envConfTemplate.TopicBufferTypes.RingBuffer,
                .buffer_size = 1024,
            },
        },
    },
};
