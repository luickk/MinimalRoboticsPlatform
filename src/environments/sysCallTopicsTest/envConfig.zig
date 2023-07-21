pub const envConfTemplate = @import("configTemplates").envConfigTemplate;
const StatusControlConf = envConfTemplate.StatusControlConf;

pub const env_config = envConfTemplate.EnvConfig(3){
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
                .buffer_size = 0x100000,
            },
        },
        .{
            .status_type = .topic,
            .name = "front-ultrasonic-proximity",
            .id = 2,
            .topic_conf = .{
                .buffer_type = envConfTemplate.TopicBufferTypes.RingBuffer,
                .buffer_size = 1024,
            },
        },
    },
};
