const kprint = @import("arm").serial.kprint;

pub fn panic() noreturn {
    kprint("[bootloader] panic \n", .{});
    while (true) {}
}
