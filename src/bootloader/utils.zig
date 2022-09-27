const bprint = @import("arm").serial.bprint;

pub fn panic() noreturn {
    bprint("[bootloader] panic \n", .{});
    while (true) {}
}
