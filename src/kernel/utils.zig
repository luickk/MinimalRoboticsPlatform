const kprint = @import("periph").uart.UartWriter(.ttbr0).kprint;

pub fn panic() noreturn {
    kprint("[kernel] panic \n", .{});
    while (true) {}
}
