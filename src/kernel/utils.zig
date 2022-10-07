const kprint = @import("periph").uart.UartWriter(.ttbr0).kprint;

pub fn panic() noreturn {
    kprint("[bootloader] panic \n", .{});
    while (true) {}
}
