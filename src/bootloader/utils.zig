const bprint = @import("peripherals").serial.bprint;

pub fn panic() noreturn {
    bprint("[bootloader] panic \n", .{});
    while (true) {}
}
