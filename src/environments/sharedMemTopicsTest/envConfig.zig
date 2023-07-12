pub const envConfTemplate = @import("configTemplates").envConfigTemplate;
const StatusControlConf = envConfTemplate.EnvConfig.StatusControlConf;

pub const env_config = envConfTemplate.EnvConfig{
    .status_control = [_]StatusControlConf{
        .{    
            .status_type = .topic,
            .name = "height-sensor",
            .topic_conf = .{
                .buffer_type = envConfTemplate.EnvConfig.TopicBufferTypes.RingBuffer,
                .buffer_size = 1024,
                .id = 1,
                .debug_desc = "test",
            },        
        },
        .{
            .status_type = .topic,
            .name = "radar-sensor",
            .topic_conf = .{
                .buffer_type = envConfTemplate.EnvConfig.TopicBufferTypes.RingBuffer,
                .buffer_size = 1024,
                .id = 2,
                .debug_desc = "test",
            },      
        },
    },
};