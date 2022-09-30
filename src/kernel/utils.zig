const kprint = @import("periph").uart.UartWriter(false).kprint;

pub fn panic() noreturn {
    kprint("[bootloader] panic \n", .{});
    while (true) {}
}
