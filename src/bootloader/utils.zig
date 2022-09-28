const kprint = @import("arm").uart.UartWriter(false).kprint;

pub fn panic() noreturn {
    kprint("[bootloader] panic \n", .{});
    while (true) {}
}
