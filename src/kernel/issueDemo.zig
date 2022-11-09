pub fn IssueDemo() type {
    return struct {
        const Self = @This();

        mem_start: usize,

        pub fn init(mem_start: usize) Self {
            return Self{
                .mem_start = mem_start,
            };
        }
    };
}
