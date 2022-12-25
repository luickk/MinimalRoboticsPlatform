const std = @import("std");

const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr1).kprint;

export fn app_main() linksection(".text.main") callconv(.Naked) noreturn {
    while (true) {
        kprint("app2 test print \n", .{});
    }
}
