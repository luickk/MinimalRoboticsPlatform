const kprint = @import("peripherals").serial.kprint;

pub fn panic() noreturn {
    kprint("[bootloader] panic \n", .{});
    while (true) {}
}
