const std = @import("std");

const periph = @import("periph");
const kprint = periph.uart.UartWriter(.ttbr1).kprint;

export fn app_main() linksection(".text.main") callconv(.Naked) noreturn {
    while (true) {
        kprint("app1 test print > {d} < \n", .{getCurrentEl()});
    }
}

fn getCurrentEl() usize {
    var x: usize = asm ("mrs %[curr], CurrentEL"
        : [curr] "=r" (-> usize),
    );
    return x >> 2;
}
